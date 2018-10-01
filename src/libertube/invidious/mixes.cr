class MixVideo
  add_mapping({
    title:          String,
    id:             String,
    author:         String,
    ucid:           String,
    length_seconds: Int32,
    index:          Int32,
  })
end

class Mix
  add_mapping({
    title:  String,
    id:     String,
    videos: Array(MixVideo),
  })
end

def fetch_mix(rdid, video_id, cookies = nil)
  client = make_client(YT_URL)
  headers = HTTP::Headers.new
  headers["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"

  if cookies
    headers = cookies.add_request_headers(headers)
  end
  response = client.get("/watch?v=#{video_id}&list=#{rdid}&bpctr=#{Time.new.epoch + 2000}&gl=US&hl=en", headers)

  yt_data = response.body.match(/window\["ytInitialData"\] = (?<data>.*);/)
  if yt_data
    yt_data = JSON.parse(yt_data["data"].rchop(";"))
  else
    raise "Could not create mix."
  end

  playlist = yt_data["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]
  mix_title = playlist["title"].as_s

  contents = playlist["contents"].as_a
  until contents[0]["playlistPanelVideoRenderer"]["videoId"].as_s == video_id
    contents.shift
  end

  videos = [] of MixVideo
  contents.each do |item|
    item = item["playlistPanelVideoRenderer"]

    id = item["videoId"].as_s
    title = item["title"]["simpleText"].as_s
    author = item["longBylineText"]["runs"][0]["text"].as_s
    ucid = item["longBylineText"]["runs"][0]["navigationEndpoint"]["browseEndpoint"]["browseId"].as_s
    length_seconds = decode_length_seconds(item["lengthText"]["simpleText"].as_s)
    index = item["navigationEndpoint"]["watchEndpoint"]["index"].as_i

    videos << MixVideo.new(
      title,
      id,
      author,
      ucid,
      length_seconds,
      index
    )
  end

  if !cookies
    next_page = fetch_mix(rdid, videos[-1].id, response.cookies)
    videos += next_page.videos
  end

  videos.uniq! { |video| video.id }
  videos = videos.first(50)
  return Mix.new(mix_title, rdid, videos)
end
