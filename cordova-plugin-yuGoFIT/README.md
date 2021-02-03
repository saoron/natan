[![npm version](https://badge.fury.io/js/cordova-plugin-yugotfit.svg)](https://badge.fury.io/js/cordova-plugin-yugotfit)

# PhoneGap/Cordova RTSP player using VLC

## Installation

    cordova plugin add cordova-plugin-yugotfit

## Supported Platforms

- Android
- iOS

## Usage

```
window.VideoPlayerVLC.play(
	 url,
	 done => {},
	 error => {}
);
```

## Response

done: string - "onDestroyVlc"

## Example:

```
window.VideoPlayerVLC.play(
	 "rtsp://192.168.42.1/live.mov",
	 done => {},
	 error => {}
);
```

References:

https://github.com/disono/libVLC-Player by [@disono](https://github.com/disono)

https://github.com/pengyanb/com.pengyanb.vlcstreamplayer by [@pengyanb](https://github.com/pengyanb)
