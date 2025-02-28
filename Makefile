PREFIX ?= $(HOME)/.local
BIN_DIR := $(PREFIX)/bin

PROG_NAME := pasteme
PROG_VERSION := $(shell cat ./VERSION | tr -d '[:space:]')

SRC_DIR := ./src
DEPS_DIR := ./deps
BUILD_DIR := ./build

ARGS += -collection:src=$(SRC_DIR)
ARGS += -collection:deps=$(DEPS_DIR)
ARGS += -out:$(BUILD_DIR)/$(PROG_NAME)
ARGS += -build-mode:exe
ARGS += -vet
ARGS += -disallow-do
ARGS += -warnings-as-errors
ARGS += -use-separate-modules
ARGS += -define:PROG_NAME=$(PROG_NAME)
ARGS += -define:PROG_VERSION=$(PROG_VERSION)

.PHONY: release debug install clean mkdir

debug: mkdir
	odin build $(SRC_DIR) $(ARGS) -debug

release: mkdir
	odin build $(SRC_DIR) $(ARGS) -o:speed

benchmark: mkdir
	odin build $(SRC_DIR) $(ARGS) -o:speed -debug

install: release
	install -Dt $(BIN_DIR) $(BUILD_DIR)/$(PROG_NAME)

clean: 
	rm -r $(BUILD_DIR)

mkdir:
ifeq ($(wildcard $(BUILD_DIR)/.),)
	mkdir -p $(BUILD_DIR)
endif
