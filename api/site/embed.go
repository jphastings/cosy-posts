package site

import "embed"

//go:embed static/css/style.css
var styleCSS []byte

//go:embed static/img/bookmark.svg
var bookmarkSVG []byte

//go:embed static/img/bookmarked.svg
var bookmarkedSVG []byte

//go:embed static/img/email.svg
var emailSVG []byte

//go:embed static/img/info.svg
var infoSVG []byte

//go:embed static/img/signal.svg
var signalSVG []byte

//go:embed static/img/whatsapp.svg
var whatsappSVG []byte

//go:embed static/img/trash.svg
var trashSVG []byte

//go:embed static/img/muted.svg
var mutedSVG []byte

//go:embed static/img/unmuted.svg
var unmutedSVG []byte

//go:embed static/img/pause.svg
var pauseSVG []byte

//go:embed templates/*
var templateFS embed.FS
