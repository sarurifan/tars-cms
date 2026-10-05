module github.com/tars-cms/gateway/wx-bff

go 1.22

require (
	github.com/TarsCloud/TarsGo v1.4.6
	github.com/tars-cms/wx v0.0.0
)

require go.uber.org/automaxprocs v1.5.2 // indirect

replace github.com/tars-cms/wx => ../../wx
