# Convenience wrappers around SwiftPM and scripts/. Run `make help`.
APP := build/Graphist.app

.PHONY: help app debug universal run dev sign notarize release clean

help:
	@echo "make app        Build $(APP) (release, host architecture)"
	@echo "make debug      Build $(APP) with debug Swift + shader debug info"
	@echo "make universal  Build $(APP) for arm64 + x86_64"
	@echo "make run        Build and launch $(APP)"
	@echo "make dev        Run via 'swift run' with live shader sources (edit Shaders/, press Cmd-R)"
	@echo "make sign       Developer ID sign only     (needs DEVELOPER_ID=...)"
	@echo "make notarize   Sign + notarize + staple   (needs DEVELOPER_ID=..., NOTARY_PROFILE=...)"
	@echo "make release    Universal build + notarize"
	@echo "make clean      Remove build products"

app:
	./scripts/build-app.sh

debug:
	CONFIG=debug ./scripts/build-app.sh

universal:
	UNIVERSAL=1 ./scripts/build-app.sh

run: app
	open $(APP)

dev:
	GRAPHIST_SHADER_DIR="$(CURDIR)/Shaders" swift run Graphist

sign:
	./scripts/sign-and-notarize.sh --sign-only

notarize:
	./scripts/sign-and-notarize.sh

release:
	UNIVERSAL=1 ./scripts/build-app.sh
	./scripts/sign-and-notarize.sh

clean:
	rm -rf .build build
