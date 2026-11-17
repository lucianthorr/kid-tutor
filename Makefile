KIT := Packages/KidTutorKit

# Machine-specific settings, not committed: copy Local.mk.example to Local.mk. project.yml reads
# DEVELOPMENT_TEAM and BUNDLE_ID when the project is generated; the team is only needed for a real iPad.
-include Local.mk
BUNDLE_ID ?= com.example.kidtutor
export DEVELOPMENT_TEAM BUNDLE_ID

# With only the Command Line Tools installed, SwiftPM can't find the Testing framework
# or initialize its default build system; point it at the CLT copy instead.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
SWIFT_TEST_FLAGS := --build-system native -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

SIM_NAME := Kid Tutor iPad
SIM_TYPE := com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
DERIVED := build/DerivedData
SIM_DATA = $$(xcrun simctl get_app_container "$(SIM_NAME)" $(BUNDLE_ID) data)
APP := $(DERIVED)/Build/Products/Debug-iphonesimulator/KidTutor.app

.PHONY: bundle-id test project open export sim-device sim screenshot wireframes logs device-logs syslog selfcheck

# The app's bundle id from Local.mk, for commands like `xcrun simctl launch "Kid Tutor iPad" $(make -s bundle-id)`.
bundle-id:
	@echo $(BUNDLE_ID)

test:
	cd $(KIT) && swift test $(SWIFT_TEST_FLAGS)

project:
	xcodegen generate

open: project
	open KidTutor.xcodeproj

# make export SAMPLES=$HOME/Downloads/samples.json OUT=$HOME/Desktop/kid-tutor-training
export:
	cd $(KIT) && swift run $(filter --build-system native,$(SWIFT_TEST_FLAGS)) kidtutor-export "$(abspath $(SAMPLES))" "$(abspath $(OUT))"

# Creates the "Kid Tutor iPad" simulator (13-inch iPad Pro, newest iOS runtime) if it doesn't exist.
sim-device:
	@xcrun simctl list devices | grep -q "$(SIM_NAME) (" || \
		xcrun simctl create "$(SIM_NAME)" $(SIM_TYPE) \
		$$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["isAvailable"] and any(d["identifier"]=="$(SIM_TYPE)" for d in x.get("supportedDeviceTypes",[]))]; print(r[-1]["identifier"])')

# Builds, installs and launches the app in the "Kid Tutor iPad" simulator.
sim: project sim-device
	xcodebuild -project KidTutor.xcodeproj -scheme KidTutor \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME)' -derivedDataPath $(DERIVED) -quiet build
	xcrun simctl boot "$(SIM_NAME)" 2>/dev/null || true
	# Xcode 27 replaced Simulator.app with DeviceHub.
	open "$$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null || open -a Simulator
	xcrun simctl install "$(SIM_NAME)" $(APP)
	SIMCTL_CHILD_CG_NUMERICS_SHOW_BACKTRACE=1 xcrun simctl launch --terminate-running-process "$(SIM_NAME)" $(BUNDLE_ID)

# Saves the "Kid Tutor iPad" simulator screen to design/screenshots/.
screenshot:
	xcrun simctl io "$(SIM_NAME)" screenshot "design/screenshots/$$(date +%Y%m%d-%H%M%S).png"

wireframes:
	open -a Safari design/index.html

# The app's own log (Documents/Logs) from the simulator. LINES=500 for more.
logs:
	@tail -n $${LINES:-200} "$(SIM_DATA)"/Documents/Logs/*.log

# The app's own log from the connected iPad (copied into build/device-logs). LINES=500 for more.
device-logs:
	@rm -rf build/device-logs && mkdir -p build/device-logs
	@xcrun devicectl device copy from --device "$$(xcrun devicectl list devices | grep physical | grep -m1 -oE '[0-9A-F]{8}-[0-9A-F]{16}')" \
		--domain-type appDataContainer --domain-identifier $(BUNDLE_ID) \
		--source Documents/Logs --destination build/device-logs >/dev/null
	@tail -n $${LINES:-200} build/device-logs/*.log

# Errors and faults from the system log for the app, plus the app's own log lines.
syslog:
	@xcrun simctl spawn "$(SIM_NAME)" log show --last $${LAST:-30m} --style compact \
		--predicate 'process == "KidTutor" AND (messageType == error OR messageType == fault OR subsystem == "$(BUNDLE_ID)")'

# Relaunch and score every recognizer on the saved samples; results land in the app log.
selfcheck:
	xcrun simctl launch --terminate-running-process "$(SIM_NAME)" $(BUNDLE_ID) -recognizerSelfCheck
	@sleep 10; grep "self-check" "$(SIM_DATA)"/Documents/Logs/*.log | grep -E "[0-9]+/[0-9]+$$|done" | tail -5
