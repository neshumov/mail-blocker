PROJECT = mail-tracker-blocker.xcodeproj
SCHEME  = MailTrackerBlockerApp

.PHONY: build clean open generate

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) \
	           -scheme $(SCHEME) \
	           -configuration Debug \
	           build

clean:
	xcodebuild -project $(PROJECT) clean

open: generate
	open $(PROJECT)
