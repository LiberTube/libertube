struct PlaylistVideo
  db_mapping({
    title:          String,
    id:             String,
    author:         String,
    ucid:           String,
    length_seconds: Int32,
    published:      Time,
    playlists:      Array(String),
    index:          Int32,
    live_now:       Bool,
  })
end

struct Playlist
  db_mapping({
    title:            String,
    id:               String,
    author:           String,
    author_thumbnail: String,
    ucid:             String,
    description:      String,
    description_html: String,
    video_count:      Int32,
    views:            Int64,
    updated:          Time,
  })
end

def fetch_playlist_videos(plid, page, video_count, continuation = nil, locale = nil)
  client = make_client(YT_URL)

  if continuation
    html = client.get("/watch?v=#{continuation}&list=#{plid}&gl=US&hl=en&disable_polymer=1&has_verified=1&bpctr=9999999999")
    html = XML.parse_html(html.body)

    index = html.xpath_node(%q(//span[@id="playlist-current-index"])).try &.content.to_i?
    if index
      index -= 1
    end
    index ||= 0
  else
    index = (page - 1) * 100
  end

  if video_count > 100
    url = produce_playlist_url(plid, index)

    response = client.get(url)
    response = JSON.parse(response.body)
    if !response["content_html"]? || response["content_html"].as_s.empty?
      raise translate(locale, "Empty playlist")
    end

    document = XML.parse_html(response["content_html"].as_s)
    nodeset = document.xpath_nodes(%q(.//tr[contains(@class, "pl-video")]))
    videos = extract_playlist(plid, nodeset, index)
  else
    # Playlist has less than one page of videos, so subsequent pages will be empty
    if page > 1
      videos = [] of PlaylistVideo
    else
      # Extract first page of videos
      response = client.get("/playlist?list=#{plid}&gl=US&hl=en&disable_polymer=1")
      document = XML.parse_html(response.body)
      nodeset = document.xpath_nodes(%q(.//tr[contains(@class, "pl-video")]))

      videos = extract_playlist(plid, nodeset, 0)

      if continuation
        until videos[0].id == continuation
          videos.shift
        end
      end
    end
  end

  return videos
end

def extract_playlist(plid, nodeset, index)
  videos = [] of PlaylistVideo

  nodeset.each_with_index do |video, offset|
    anchor = video.xpath_node(%q(.//td[@class="pl-video-title"]))
    if !anchor
      next
    end

    title = anchor.xpath_node(%q(.//a)).not_nil!.content.strip(" \n")
    id = anchor.xpath_node(%q(.//a)).not_nil!["href"].lchop("/watch?v=")[0, 11]

    anchor = anchor.xpath_node(%q(.//div[@class="pl-video-owner"]/a))
    if anchor
      author = anchor.content
      ucid = anchor["href"].split("/")[2]
    else
      author = ""
      ucid = ""
    end

    anchor = video.xpath_node(%q(.//td[@class="pl-video-time"]/div/div[1]))
    if anchor && !anchor.content.empty?
      length_seconds = decode_length_seconds(anchor.content)
      live_now = false
    else
      length_seconds = 0
      live_now = true
    end

    videos << PlaylistVideo.new(
      title: title,
      id: id,
      author: author,
      ucid: ucid,
      length_seconds: length_seconds,
      published: Time.now,
      playlists: [plid],
      index: index + offset,
      live_now: live_now
    )
  end

  return videos
end

def produce_playlist_url(id, index)
  if id.starts_with? "UC"
    id = "UU" + id.lchop("UC")
  end
  ucid = "VL" + id

  meta = IO::Memory.new
  meta.write(Bytes[0x08])
  meta.write(write_var_int(index))

  meta.rewind
  meta = Base64.urlsafe_encode(meta.to_slice, false)
  meta = "PT:#{meta}"

  continuation = IO::Memory.new
  continuation.write(Bytes[0x7a, meta.size])
  continuation.print(meta)

  continuation.rewind
  meta = Base64.urlsafe_encode(continuation.to_slice)
  meta = URI.escape(meta)

  continuation = IO::Memory.new
  continuation.write(Bytes[0x12, ucid.size])
  continuation.print(ucid)
  continuation.write(Bytes[0x1a, meta.size])
  continuation.print(meta)

  wrapper = IO::Memory.new
  wrapper.write(Bytes[0xe2, 0xa9, 0x85, 0xb2, 0x02, continuation.size])
  wrapper.print(continuation)
  wrapper.rewind

  wrapper = Base64.urlsafe_encode(wrapper.to_slice)
  wrapper = URI.escape(wrapper)

  url = "/browse_ajax?continuation=#{wrapper}&gl=US&hl=en"

  return url
end

def fetch_playlist(plid, locale)
  client = make_client(YT_URL)

  if plid.starts_with? "UC"
    plid = "UU#{plid.lchop("UC")}"
  end

  response = client.get("/playlist?list=#{plid}&hl=en&disable_polymer=1")
  if response.status_code != 200
    raise translate(locale, "Not a playlist.")
  end

  body = response.body.gsub(/<button[^>]+><span[^>]+>\s*less\s*<img[^>]+>\n<\/span><\/button>/, "")
  document = XML.parse_html(body)

  title = document.xpath_node(%q(//h1[@class="pl-header-title"]))
  if !title
    raise translate(locale, "Playlist does not exist.")
  end
  title = title.content.strip(" \n")

  description_html = document.xpath_node(%q(//span[@class="pl-header-description-text"]/div/div[1]))
  description_html ||= document.xpath_node(%q(//span[@class="pl-header-description-text"]))
  description_html, description = html_to_content(description_html)

  # YouTube allows anonymous playlists, so most of this can be empty or optional
  anchor = document.xpath_node(%q(//ul[@class="pl-header-details"]))
  author = anchor.try &.xpath_node(%q(.//li[1]/a)).try &.content
  author ||= ""
  author_thumbnail = document.xpath_node(%q(//img[@class="channel-header-profile-image"])).try &.["src"]
  author_thumbnail ||= ""
  ucid = anchor.try &.xpath_node(%q(.//li[1]/a)).try &.["href"].split("/")[-1]
  ucid ||= ""

  video_count = anchor.try &.xpath_node(%q(.//li[2])).try &.content.gsub(/\D/, "").to_i?
  video_count ||= 0
  views = anchor.try &.xpath_node(%q(.//li[3])).try &.content.delete("No views, ").to_i64?
  views ||= 0_i64

  updated = anchor.try &.xpath_node(%q(.//li[4])).try &.content.lchop("Last updated on ").lchop("Updated ")
  if updated
    updated = decode_date(updated)
  else
    updated = Time.now
  end

  playlist = Playlist.new(
    title: title,
    id: plid,
    author: author,
    author_thumbnail: author_thumbnail,
    ucid: ucid,
    description: description,
    description_html: description_html,
    video_count: video_count,
    views: views,
    updated: updated
  )

  return playlist
end

def template_playlist(playlist)
  html = <<-END_HTML
  <h3>
    <a href="/playlist?list=#{playlist["playlistId"]}">
      #{playlist["title"]}
    </a>
  </h3>
  <div class="pure-menu pure-menu-scrollable playlist-restricted">
    <ol class="pure-menu-list">
  END_HTML

  playlist["videos"].as_a.each do |video|
    html += <<-END_HTML
      <li class="pure-menu-item">
        <a href="/watch?v=#{video["videoId"]}&list=#{playlist["playlistId"]}">
          <div class="thumbnail">
              <img class="thumbnail" src="/vi/#{video["videoId"]}/mqdefault.jpg">
              <p class="length">#{recode_length_seconds(video["lengthSeconds"].as_i)}</p>
          </div>
          <p style="width:100%">#{video["title"]}</p>
          <p>
            <b style="width:100%">#{video["author"]}</b>
          </p>
        </a>
      </li>
    END_HTML
  end

  html += <<-END_HTML
    </ol>
  </div>
  <hr>
  END_HTML

  html
end
