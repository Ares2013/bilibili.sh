#!/usr/bin/env bash
#
# (c) 2017 Qiu Xiang <i@7c00.cc> under MIT licence
#

BASE_PATH=$(cd $(dirname $0); pwd)
DANMAKU2ASS_PATH="$BASE_PATH/danmaku2ass.py"

shopt -s expand_aliases
alias danmaku2ass="python3 $DANMAKU2ASS_PATH"
alias request="curl -s -H 'User-Agent: Mozilla/5.0 BiliDroid/5.2.3 (bbcallen@gmail.com)'"
command -v md5 > /dev/null || alias md5=md5sum

xpath() {
  xmllint $1 --html --xpath $2 2>/dev/null
}

#
# 播放视频
#
# $1 av_id
#
play() {
  echo "获取视频数据"
  local video_json=$(request "http://api.bilibili.com/view?appkey=8e9fc618fbd41e28&id=$1")
  local cid=$(jq .cid <<< ${video_json})
  local title=$(jq -r .title <<< ${video_json})
  local params="_appver=424000&_device=android&_down=0&_hwid=$RANDOM&_p=1&_tid=0&appkey=452d3958f048c02a&cid=$cid&otype=json&platform=android"
  local sign=$(echo -n ${params}f7c926f549b9becf1c27644958676a21 | md5)

  echo "获取播放链接"
  local play_json=$(request "https://interface.bilibili.com/playurl?$params&sign=${sign:0:32}")

  local error_message=$(jq .message <<< ${play_json})
  if [ -n "$error_message" ]; then
    echo "无法获取播放链接：$error_message"
    exit
  fi

  local length=$(jq ".durl | length" <<< ${play_json})
  local playlist
  for (( i = 0; i < length; i++ )) do
    playlist+="$(jq -r .durl[${i}].url <<< ${play_json}) "
  done

  echo "获取弹幕"
  local comments=$(request http://comment.bilibili.com/${cid}.xml --compressed)
  local ass=$(danmaku2ass -s 1280x720 -dm 20 -o >(cat) <(echo "$comments"))
  mpv --force-media-title "$title" -sub-file <(echo "$ass") --merge-files ${playlist}
}

#
# 获取番剧信息
#
# $1 番剧地址，如：https://bangumi.bilibili.com/anime/5992
#
bangumi() {
  echo "获取番剧信息"
  local anime_id=${1##*/}
  local anime_id=${anime_id%\?*}
  local anime_info=$(request "http://bangumi.bilibili.com/jsonp/seasoninfo/$anime_id.ver?callback=seasonListCallback")
  local anime_info=$(expr "$anime_info" : "seasonListCallback(\(.*\));")
  local title=$(jq -r .result.title <<< ${anime_info})
  local staff=$(jq -r .result.staff <<< ${anime_info})
  local intro=$(jq -r .result.evaluate <<< ${anime_info})
  local brief=$(jq -r .result.brief <<< ${anime_info})
  printf "\n$title\n"
  printf "\n$staff\n"
  printf "\n$intro\n\n"
  local length=$(jq ".result.episodes | length" <<< ${anime_info})
  for (( i = 0; i < length; i++)) do
    local index=$(jq -r .result.episodes[$[$length - $i - 1]].index <<< ${anime_info})
    local title=$(jq -r .result.episodes[$[$length - $i - 1]].index_title <<< ${anime_info})
    printf "%4d - %s %s\n" $[$i + 1] "第${index}话" "$title"
  done
  printf "\n请选择要播放的集数："
  read choice
  url=$(jq -r .result.episodes[$[$length - $choice]].webplay_url <<< ${anime_info})
  main ${url}
}

#
# 番剧搜索
#
# $1 关键字
#
search() {
  echo "搜索“$1”"
  local html=$(request "http://search.bilibili.com/all" --get --data-urlencode "keyword=$1")
  html=${html/'<meta charset="utf-8">'/<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">}
  local url=$(xpath <(echo "$html") "string(//ul[@class='so-episode']/a[1]/@href)")
  if [ -z ${url} ]; then
    echo "未找到匹配的番剧"
  else
    bangumi http:${url%\?*}
  fi
}

#
# 观看直播
#
# $1 直播间链接，如：https://live.bilibili.com/123
#
live() {
  local room_id=$(request $1 | grep -Po "ROOMID = \K\d+")
  local json=$(request "https://api.live.bilibili.com/api/playurl?cid=$room_id&otype=json")
  local url=$(echo ${json} | jq -r .durl[0].url)
  mpv ${url}
}

main() {
  local av_id
  local video_pattern=https?://www.bilibili.com/video/av[0-9]+/
  local anime_pattern=https?://bangumi.bilibili.com/anime/[0-9]+
  local anime_item_pattern=https?://bangumi.bilibili.com/anime/[0-9]+/play#[0-9]+
  local live_pattern=https?://live.bilibili.com/[0-9]+
  if [[ $1 =~ $anime_item_pattern ]]; then
    echo "获取番剧数据"
    local episode_id=${1#*#}
    local episode_json=$(request http://bangumi.bilibili.com/web_api/episode/${episode_id}.json)
    local danmaku_id=$(jq -r .result.currentEpisode.danmaku <<< ${episode_json})
    av_id=$(jq -r .result.currentEpisode.avId <<< ${episode_json})
  elif [[ $1 =~ $anime_pattern  ]]; then
    bangumi $1
    exit
  elif [[ $1 =~ $video_pattern  ]]; then
    av_id=$(expr "$1" : ".*av\(.*\)/")
  elif [[ $1 =~ $live_pattern  ]]; then
    live $1
    exit
  else
    search "$1"
    exit
  fi

  play ${av_id}
}

if [ -z $1 ]; then
  cat << EOF
Usage：bilibili 番剧名|视频地址|直播间地址
EOF
else
  main $1
fi
