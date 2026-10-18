# Rosette's checked-in macOS compatibility policy.
#
# Rosette is built on macOS 13.7.8 with Xcode 15.2 / macOS SDK 14.2. The
# deployment target is the compatibility contract: binaries advertise the
# macOS 13.0 floor and must guard APIs introduced later. The SDK/Xcode values
# document the reference toolchain; builds use the active local SDK because
# Apple system frameworks cannot be frozen or redistributed with Rosette.
ROSETTE_MACOS_DEPLOYMENT_TARGET ?= 13.0
ROSETTE_REFERENCE_XCODE_VERSION := 15.2
ROSETTE_REFERENCE_MACOS_SDK_VERSION := 14.2
