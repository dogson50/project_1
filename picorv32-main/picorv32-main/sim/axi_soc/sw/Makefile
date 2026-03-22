TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
PYTHON ?= python3
HEX_WORDS ?= 16384

CC      := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY := $(TOOLCHAIN_PREFIX)objcopy

CFLAGS  := -Os -mabi=ilp32 -march=rv32im -ffreestanding -nostdlib -Wall -Wextra
LDFLAGS := -nostdlib -Wl,--build-id=none,-Bstatic,-T,sections_axi_soc.lds,-Map,demo.map,--strip-debug

all: demo.hex

demo.elf: start.o main.o sections_axi_soc.lds
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.o main.o -lgcc

demo.bin: demo.elf
	$(OBJCOPY) -O binary $< $@

demo.hex: demo.bin ../../../firmware/makehex.py
	$(PYTHON) ../../../firmware/makehex.py demo.bin $(HEX_WORDS) > $@

start.o: start.S
	$(CC) -c $(CFLAGS) -o $@ $<

main.o: main.c
	$(CC) -c $(CFLAGS) -std=c11 -o $@ $<

clean:
	rm -f start.o main.o demo.elf demo.bin demo.hex demo.map

.PHONY: all clean

