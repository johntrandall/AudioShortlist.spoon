# AudioShortlist.spoon: test, lint, build docs.json, and package the release archive.
SPOON := AudioShortlist.spoon
FILES := init.lua core.lua docs.json LICENSE

.PHONY: test lint docs zip clean

test:
	lua tests/run.lua

lint:
	luacheck core.lua init.lua tests/run.lua

# Needs Hammerspoon running; uses its built-in hs.doc.builder.
docs:
	hs -c 'local p="$(CURDIR)/"; local f=io.open(p.."docs.json","w"); f:write(hs.doc.builder.genJSON(p.."init.lua")); f:close(); return "docs.json written"' </dev/null

# dist/AudioShortlist.spoon.zip holds one folder, AudioShortlist.spoon, with the runtime files only.
zip: test
	rm -rf dist && mkdir -p dist/$(SPOON)
	cp $(FILES) dist/$(SPOON)/
	cd dist && zip -qrX $(SPOON).zip $(SPOON)
	@unzip -l dist/$(SPOON).zip

clean:
	rm -rf dist
