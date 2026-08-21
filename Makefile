.DEFAULT_GOAL := help
.PHONY: help test doctor sync deps build package all
help:
	@./bin/ardour-ci --help
test:
	@./tests/run.sh
doctor:
	@./bin/ardour-ci doctor
sync:
	@./bin/ardour-ci deps sync
deps:
	@./bin/ardour-ci deps build
build:
	@./bin/ardour-ci build
package:
	@./bin/ardour-ci package
all:
	@./bin/ardour-ci all
