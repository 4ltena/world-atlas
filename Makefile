CONF ?= release
APP  := WorldAtlas.app
BIN  := WorldAtlasApp

.PHONY: app run test clean

app:
	swift build -c $(CONF) --product $(BIN)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/Info.plist
	cp "$$(swift build -c $(CONF) --show-bin-path)/$(BIN)" $(APP)/Contents/MacOS/$(BIN)
	# GRDB の資源の束。GRDB 7.11 自身は Bundle.module を一度も呼ばないが、将来の版が
	# 呼んだときに fatalError で落ちないための保険である。Contents/Resources へ写す。
	# 生成される Bundle.module は Bundle.main.bundleURL 直下（.app 直下）も探すが、
	# .app 直下に裸の束を置くと macOS 26 の codesign が
	# "unsealed contents present in the bundle root" で署名を拒む。Contents 配下に
	# 置く方を優先する。
	for b in "$$(swift build -c $(CONF) --show-bin-path)"/*.bundle; do \
		if [ -e "$$b" ]; then cp -R "$$b" $(APP)/Contents/Resources/; fi; \
	done
	codesign --force --sign - $(APP)

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf $(APP) .build
