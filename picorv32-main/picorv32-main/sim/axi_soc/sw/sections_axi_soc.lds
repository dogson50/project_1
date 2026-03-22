MEMORY {
	prog : ORIGIN = 0x00000000, LENGTH = 0x00010000
	data : ORIGIN = 0x20000000, LENGTH = 0x00010000
}

SECTIONS {
	.text : {
		. = ALIGN(4);
		KEEP(*(.text.start))
		*(.text*)
		*(.rodata*)
		. = ALIGN(4);
	} > prog

	.data : {
		. = ALIGN(4);
		*(.data*)
		. = ALIGN(4);
	} > data AT > prog

	.bss (NOLOAD) : {
		. = ALIGN(4);
		*(.bss*)
		*(COMMON)
		. = ALIGN(4);
	} > data

	/DISCARD/ : {
		*(.eh_frame*)
		*(.comment*)
	}
}

