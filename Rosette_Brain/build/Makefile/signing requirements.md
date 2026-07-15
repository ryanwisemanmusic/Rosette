Any developer that wishes to create their own signed version of this application is required to be part of the Apple Developer Program. Xcode should be your means of managing certificates OUTSIDE of the repo. I am not responsible if your certs or keys leak if you fork this project and host these inside of the repo

For signing, the policy is BYOK (bring your own keys) as is standard with most repos. The relevant code to changing your credentials is here:
```Makefile
CREDENTIALS := /absolute/path/of/your/.env-file

-include $(CREDENTIALS)

export
```

Please do not touch this code unless you need an expansion on the flags or how you tag releases:
```Makefile
ifneq ($(APPLE_DEVELOPER_ID),)

CODESIGN_IDENTITY ?= $(APPLE_DEVELOPER_ID)

INSTALLER_SIGN_IDENTITY ?= $(APPLE_INSTALLER_ID)

CODESIGN_EXTRA_FLAGS ?= --timestamp --options runtime

BUILD_TYPE := "Official Release"

else

CODESIGN_IDENTITY ?= -

INSTALLER_SIGN_IDENTITY ?= -

CODESIGN_EXTRA_FLAGS ?=

BUILD_TYPE := "Developer Build (Ad-hoc)"

endif
```

This is setup in such a way in which because of the .env files, it holds several of the values I use related to how I store these secrets. So if you use a different schema, please ensure it reflects accordingly. However, in case you want a structure of the .env file... This is a good format to use:
```env-file
APPLE_TEAM_ID="???"
APPLE_DEVELOPER_ID="Developer ID Application: ??? (???)"
APPLE_INSTALLER_ID="Developer ID Installer: ??? (???)"
APPLE_ID="youremail@host.extension"
APPLE_APP_SPECIFIC_PASSWORD="shhhhhh-its-a-secret"
```

Please do not be that person that allows a cloud based language model to view this data. Whilst the password is what you generate via account.apple.com and is the most important thing to protect, nowhere should you ever have this data read by any one/thing else but yourself.

To ensure that you've handled everything regarding keys, here is the make command you can run to verify that your key is accepted prior to running 'make app-all':
```Makefile
.PHONY: verify-creds

verify-creds:

@echo 'Build Type: $(BUILD_TYPE)'

@echo 'CODESIGN_IDENTITY: $(CODESIGN_IDENTITY)'

@echo 'CODESIGN_EXTRA_FLAGS: $(CODESIGN_EXTRA_FLAGS)'

@echo 'APPLE_DEVELOPER_ID: $(APPLE_DEVELOPER_ID)'

@echo 'APPLE_TEAM_ID: $(APPLE_TEAM_ID)'

@echo 'APPLE_ID: $(APPLE_ID)'

@echo 'APP_PASSWORD: [HIDDEN]'
```
There is no reason to ever output the value of the password you've created even in testing, given that everything should be straight forward. Any mismatch means you'll be unable to sign this application, and please verify that you are managing your certificates properly in Xcode given that this is a common point of failure.

