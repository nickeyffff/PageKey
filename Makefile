APP_NAME    := PageKey
VERSION     := 1.0.0
BUILD_DIR   := .build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
BIN         := $(BUILD_DIR)/pagekey
INSTALL_DIR := $(HOME)/Applications
SWIFTC      := swiftc
FLAGS       := -O
IDENT       := local.pagekey.windowsapp

.PHONY: all build app install uninstall reset run version clean

all: app

## 编译可执行文件
build: $(BIN)

$(BIN): Sources/PageKey/main.swift
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(FLAGS) Sources/PageKey/main.swift -o $(BIN)
	@echo "✓ $(BIN)"

## 打包成 .app（ad-hoc 签名）
app: $(APP_BUNDLE)

$(APP_BUNDLE): $(BIN) Resources/Info.plist
	@if [ -d $(APP_BUNDLE) ]; then mv $(APP_BUNDLE) "/tmp/pagekey-old-$$$$.app"; fi
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	@cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/pagekey
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@# 可执行文件本身已由链接器完成 ad-hoc 签名；这里对 bundle 再签一次（失败不致命）
	@codesign --force --sign - --identifier $(IDENT) $(APP_BUNDLE) 2>/dev/null || true
	@echo "✓ $(APP_BUNDLE)"

## 安装到 ~/Applications
install: app
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/"
	@codesign --force --sign - --identifier $(IDENT) "$(INSTALL_DIR)/$(APP_NAME).app" 2>/dev/null
	@echo "✓ 已安装: $(INSTALL_DIR)/$(APP_NAME).app"

## 卸载并恢复正常键位
uninstall: 
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@$(BIN) --reset 2>/dev/null || echo "   （无残留映射）"
	@echo "✓ 已卸载"

## 查看当前前台 App 的 bundle id
run: build
	@$(BIN) --list

## 清除全局键位映射
reset: build
	@$(BIN) --reset

version:
	@echo $(VERSION)

clean:
	@rm -rf $(BUILD_DIR)
	@echo "✓ 已清理"
