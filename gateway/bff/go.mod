module github.com/tars-cms/gateway/bff

go 1.22

require (
	github.com/TarsCloud/TarsGo v1.4.6
	github.com/tars-cms/cms v0.0.0
)

require go.uber.org/automaxprocs v1.5.2 // indirect

replace github.com/tars-cms/cms => ../../cms
