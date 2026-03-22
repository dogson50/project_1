// This is free and unencumbered software released into the public domain.
//
// Anyone is free to copy, modify, publish, use, compile, sell, or
// distribute this software, either in source code form or as a compiled
// binary, for any purpose, commercial or non-commercial, and by any
// means.

#define ENABLE_QREGS
#define ENABLE_HELLO
#define ENABLE_RVTST
#define ENABLE_SIEVE
#define ENABLE_MULTST
#define ENABLE_STATS

#ifndef ENABLE_QREGS
#  undef ENABLE_RVTST
#endif

// Only save registers in IRQ wrapper that are to be saved by the caller in
// the RISC-V ABI, with the excpetion of the stack pointer. The IRQ handler
// will save the rest if necessary. I.e. skip x3, x4, x8, x9, and x18-x27.
#undef ENABLE_FASTIRQ

#include "custom_ops.S"

/*
 * 本固件的启动/中断总览
 * --------------------
 * 1) CPU 复位后先进入 reset_vec，再跳转到 start。
 * 2) start 才是该裸机镜像的真实程序入口。
 *    这里没有标准 C runtime 的 crt0 -> main() 启动链。
 * 3) IRQ/Trap 进入 irq_vec，保存上下文后调用 C 处理函数 irq()
 *    （定义在 firmware/irq.c）。
 * 4) start 的演示流程最后会打印 DONE 并执行 ebreak。
 */

	.section .text
	.global irq
	.global hello
	.global sieve
	.global multest
	.global hard_mul
	.global hard_mulh
	.global hard_mulhsu
	.global hard_mulhu
	.global hard_div
	.global hard_divu
	.global hard_rem
	.global hard_remu
	.global stats

reset_vec:
	// 保持复位桩代码尽量短小。
	// 核心在复位释放后会先跳到这里。
	picorv32_waitirq_insn(zero)
	picorv32_maskirq_insn(zero, zero)
	// 转交给真正的启动流程。
	j start


/* Interrupt handler
 **********************************/

.balign 16
irq_vec:
	/*
	 * IRQ/Trap 底层入口：
	 * 保存机器上下文 -> 调用 C 处理函数 -> 恢复上下文 -> 通过 retirq 返回
	 * （retirq 在本函数底部）。
	 */

#ifdef ENABLE_QREGS

	picorv32_setq_insn(q2, x1)
	picorv32_setq_insn(q3, x2)

	lui x1, %hi(irq_regs)
	addi x1, x1, %lo(irq_regs)

	picorv32_getq_insn(x2, q0)
	sw x2,   0*4(x1)

	picorv32_getq_insn(x2, q2)
	sw x2,   1*4(x1)

	picorv32_getq_insn(x2, q3)
	sw x2,   2*4(x1)

#ifdef ENABLE_FASTIRQ
	sw x5,   5*4(x1)
	sw x6,   6*4(x1)
	sw x7,   7*4(x1)
	sw x10, 10*4(x1)
	sw x11, 11*4(x1)
	sw x12, 12*4(x1)
	sw x13, 13*4(x1)
	sw x14, 14*4(x1)
	sw x15, 15*4(x1)
	sw x16, 16*4(x1)
	sw x17, 17*4(x1)
	sw x28, 28*4(x1)
	sw x29, 29*4(x1)
	sw x30, 30*4(x1)
	sw x31, 31*4(x1)
#else
	sw x3,   3*4(x1)
	sw x4,   4*4(x1)
	sw x5,   5*4(x1)
	sw x6,   6*4(x1)
	sw x7,   7*4(x1)
	sw x8,   8*4(x1)
	sw x9,   9*4(x1)
	sw x10, 10*4(x1)
	sw x11, 11*4(x1)
	sw x12, 12*4(x1)
	sw x13, 13*4(x1)
	sw x14, 14*4(x1)
	sw x15, 15*4(x1)
	sw x16, 16*4(x1)
	sw x17, 17*4(x1)
	sw x18, 18*4(x1)
	sw x19, 19*4(x1)
	sw x20, 20*4(x1)
	sw x21, 21*4(x1)
	sw x22, 22*4(x1)
	sw x23, 23*4(x1)
	sw x24, 24*4(x1)
	sw x25, 25*4(x1)
	sw x26, 26*4(x1)
	sw x27, 27*4(x1)
	sw x28, 28*4(x1)
	sw x29, 29*4(x1)
	sw x30, 30*4(x1)
	sw x31, 31*4(x1)
#endif

#else // ENABLE_QREGS

#ifdef ENABLE_FASTIRQ
	sw gp,   0*4+0x200(zero)
	sw x1,   1*4+0x200(zero)
	sw x2,   2*4+0x200(zero)
	sw x5,   5*4+0x200(zero)
	sw x6,   6*4+0x200(zero)
	sw x7,   7*4+0x200(zero)
	sw x10, 10*4+0x200(zero)
	sw x11, 11*4+0x200(zero)
	sw x12, 12*4+0x200(zero)
	sw x13, 13*4+0x200(zero)
	sw x14, 14*4+0x200(zero)
	sw x15, 15*4+0x200(zero)
	sw x16, 16*4+0x200(zero)
	sw x17, 17*4+0x200(zero)
	sw x28, 28*4+0x200(zero)
	sw x29, 29*4+0x200(zero)
	sw x30, 30*4+0x200(zero)
	sw x31, 31*4+0x200(zero)
#else
	sw gp,   0*4+0x200(zero)
	sw x1,   1*4+0x200(zero)
	sw x2,   2*4+0x200(zero)
	sw x3,   3*4+0x200(zero)
	sw x4,   4*4+0x200(zero)
	sw x5,   5*4+0x200(zero)
	sw x6,   6*4+0x200(zero)
	sw x7,   7*4+0x200(zero)
	sw x8,   8*4+0x200(zero)
	sw x9,   9*4+0x200(zero)
	sw x10, 10*4+0x200(zero)
	sw x11, 11*4+0x200(zero)
	sw x12, 12*4+0x200(zero)
	sw x13, 13*4+0x200(zero)
	sw x14, 14*4+0x200(zero)
	sw x15, 15*4+0x200(zero)
	sw x16, 16*4+0x200(zero)
	sw x17, 17*4+0x200(zero)
	sw x18, 18*4+0x200(zero)
	sw x19, 19*4+0x200(zero)
	sw x20, 20*4+0x200(zero)
	sw x21, 21*4+0x200(zero)
	sw x22, 22*4+0x200(zero)
	sw x23, 23*4+0x200(zero)
	sw x24, 24*4+0x200(zero)
	sw x25, 25*4+0x200(zero)
	sw x26, 26*4+0x200(zero)
	sw x27, 27*4+0x200(zero)
	sw x28, 28*4+0x200(zero)
	sw x29, 29*4+0x200(zero)
	sw x30, 30*4+0x200(zero)
	sw x31, 31*4+0x200(zero)
#endif

#endif // ENABLE_QREGS

	/*
	 * 调用 C 中断处理函数：
	 *   a0 = 已保存寄存器现场的指针
	 *   a1 = irq/trap 原因位图/类型
	 * C 函数符号：firmware/irq.c 中的 irq()
	 */

	lui sp, %hi(irq_stack)
	addi sp, sp, %lo(irq_stack)

	// arg0 = address of regs
	lui a0, %hi(irq_regs)
	addi a0, a0, %lo(irq_regs)

	// arg1 = interrupt type
#ifdef ENABLE_QREGS
	picorv32_getq_insn(a1, q1)
#else
	addi a1, tp, 0
#endif

	// 调用 C 的 IRQ 处理函数。
	jal ra, irq

	/* 恢复保存的寄存器并从 IRQ/Trap 返回。 */

#ifdef ENABLE_QREGS

	// new irq_regs address returned from C code in a0
	addi x1, a0, 0

	lw x2,   0*4(x1)
	picorv32_setq_insn(q0, x2)

	lw x2,   1*4(x1)
	picorv32_setq_insn(q1, x2)

	lw x2,   2*4(x1)
	picorv32_setq_insn(q2, x2)

#ifdef ENABLE_FASTIRQ
	lw x5,   5*4(x1)
	lw x6,   6*4(x1)
	lw x7,   7*4(x1)
	lw x10, 10*4(x1)
	lw x11, 11*4(x1)
	lw x12, 12*4(x1)
	lw x13, 13*4(x1)
	lw x14, 14*4(x1)
	lw x15, 15*4(x1)
	lw x16, 16*4(x1)
	lw x17, 17*4(x1)
	lw x28, 28*4(x1)
	lw x29, 29*4(x1)
	lw x30, 30*4(x1)
	lw x31, 31*4(x1)
#else
	lw x3,   3*4(x1)
	lw x4,   4*4(x1)
	lw x5,   5*4(x1)
	lw x6,   6*4(x1)
	lw x7,   7*4(x1)
	lw x8,   8*4(x1)
	lw x9,   9*4(x1)
	lw x10, 10*4(x1)
	lw x11, 11*4(x1)
	lw x12, 12*4(x1)
	lw x13, 13*4(x1)
	lw x14, 14*4(x1)
	lw x15, 15*4(x1)
	lw x16, 16*4(x1)
	lw x17, 17*4(x1)
	lw x18, 18*4(x1)
	lw x19, 19*4(x1)
	lw x20, 20*4(x1)
	lw x21, 21*4(x1)
	lw x22, 22*4(x1)
	lw x23, 23*4(x1)
	lw x24, 24*4(x1)
	lw x25, 25*4(x1)
	lw x26, 26*4(x1)
	lw x27, 27*4(x1)
	lw x28, 28*4(x1)
	lw x29, 29*4(x1)
	lw x30, 30*4(x1)
	lw x31, 31*4(x1)
#endif

	picorv32_getq_insn(x1, q1)
	picorv32_getq_insn(x2, q2)

#else // ENABLE_QREGS

	// new irq_regs address returned from C code in a0
	addi a1, zero, 0x200
	beq a0, a1, 1f
	ebreak
1:

#ifdef ENABLE_FASTIRQ
	lw gp,   0*4+0x200(zero)
	lw x1,   1*4+0x200(zero)
	lw x2,   2*4+0x200(zero)
	lw x5,   5*4+0x200(zero)
	lw x6,   6*4+0x200(zero)
	lw x7,   7*4+0x200(zero)
	lw x10, 10*4+0x200(zero)
	lw x11, 11*4+0x200(zero)
	lw x12, 12*4+0x200(zero)
	lw x13, 13*4+0x200(zero)
	lw x14, 14*4+0x200(zero)
	lw x15, 15*4+0x200(zero)
	lw x16, 16*4+0x200(zero)
	lw x17, 17*4+0x200(zero)
	lw x28, 28*4+0x200(zero)
	lw x29, 29*4+0x200(zero)
	lw x30, 30*4+0x200(zero)
	lw x31, 31*4+0x200(zero)
#else
	lw gp,   0*4+0x200(zero)
	lw x1,   1*4+0x200(zero)
	lw x2,   2*4+0x200(zero)
	// do not restore x3 (gp)
	lw x4,   4*4+0x200(zero)
	lw x5,   5*4+0x200(zero)
	lw x6,   6*4+0x200(zero)
	lw x7,   7*4+0x200(zero)
	lw x8,   8*4+0x200(zero)
	lw x9,   9*4+0x200(zero)
	lw x10, 10*4+0x200(zero)
	lw x11, 11*4+0x200(zero)
	lw x12, 12*4+0x200(zero)
	lw x13, 13*4+0x200(zero)
	lw x14, 14*4+0x200(zero)
	lw x15, 15*4+0x200(zero)
	lw x16, 16*4+0x200(zero)
	lw x17, 17*4+0x200(zero)
	lw x18, 18*4+0x200(zero)
	lw x19, 19*4+0x200(zero)
	lw x20, 20*4+0x200(zero)
	lw x21, 21*4+0x200(zero)
	lw x22, 22*4+0x200(zero)
	lw x23, 23*4+0x200(zero)
	lw x24, 24*4+0x200(zero)
	lw x25, 25*4+0x200(zero)
	lw x26, 26*4+0x200(zero)
	lw x27, 27*4+0x200(zero)
	lw x28, 28*4+0x200(zero)
	lw x29, 29*4+0x200(zero)
	lw x30, 30*4+0x200(zero)
	lw x31, 31*4+0x200(zero)
#endif

#endif // ENABLE_QREGS

	picorv32_retirq_insn()

.balign 0x200
irq_regs:
	// registers are saved to this memory region during interrupt handling
	// the program counter is saved as register 0
	.fill 32,4

	// stack for the interrupt handler
	.fill 128,4
irq_stack:


/* Main program
 **********************************/

start:
	/*
	 * 该标签就是固件真实入口。
	 * 本项目由汇编完全控制启动过程，
	 * 因此不存在常见宿主程序中的 crt0/main() 启动链。
	 */
	/* zero-initialize all registers */

	addi x1, zero, 0
	addi x2, zero, 0
	addi x3, zero, 0
	addi x4, zero, 0
	addi x5, zero, 0
	addi x6, zero, 0
	addi x7, zero, 0
	addi x8, zero, 0
	addi x9, zero, 0
	addi x10, zero, 0
	addi x11, zero, 0
	addi x12, zero, 0
	addi x13, zero, 0
	addi x14, zero, 0
	addi x15, zero, 0
	addi x16, zero, 0
	addi x17, zero, 0
	addi x18, zero, 0
	addi x19, zero, 0
	addi x20, zero, 0
	addi x21, zero, 0
	addi x22, zero, 0
	addi x23, zero, 0
	addi x24, zero, 0
	addi x25, zero, 0
	addi x26, zero, 0
	addi x27, zero, 0
	addi x28, zero, 0
	addi x29, zero, 0
	addi x30, zero, 0
	addi x31, zero, 0

#ifdef ENABLE_HELLO
	/* set stack pointer */
	lui sp,(128*1024)>>12

	/* 调用 firmware/hello.c 中的 hello() */
	jal ra,hello
#endif

	/* 执行已链接进镜像的 riscv-tests 指令测试。 */

#ifdef ENABLE_RVTST
#  define TEST(n) \
	.global n; \
	addi x1, zero, 1000; \
	picorv32_timer_insn(zero, x1); \
	jal zero,n; \
	.global n ## _ret; \
	n ## _ret:
#else
#  define TEST(n) \
	.global n ## _ret; \
	n ## _ret:
#endif

	TEST(lui)
	TEST(auipc)
	TEST(j)
	TEST(jal)
	TEST(jalr)

	TEST(beq)
	TEST(bne)
	TEST(blt)
	TEST(bge)
	TEST(bltu)
	TEST(bgeu)

	TEST(lb)
	TEST(lh)
	TEST(lw)
	TEST(lbu)
	TEST(lhu)

	TEST(sb)
	TEST(sh)
	TEST(sw)

	TEST(addi)
	TEST(slti) // also tests sltiu
	TEST(xori)
	TEST(ori)
	TEST(andi)
	TEST(slli)
	TEST(srli)
	TEST(srai)

	TEST(add)
	TEST(sub)
	TEST(sll)
	TEST(slt) // what is with sltu ?
	TEST(xor)
	TEST(srl)
	TEST(sra)
	TEST(or)
	TEST(and)

	TEST(mulh)
	TEST(mulhsu)
	TEST(mulhu)
	TEST(mul)

	TEST(div)
	TEST(divu)
	TEST(rem)
	TEST(remu)

	TEST(simple)

	/* 在调用后续 C 函数前重新设置栈指针。 */
	lui sp,(128*1024)>>12

	/* set gp and tp */
	lui gp, %hi(0xdeadbeef)
	addi gp, gp, %lo(0xdeadbeef)
	addi tp, gp, 0

#ifdef ENABLE_SIEVE
	/* 调用 C 侧 sieve() 示例/基准。 */
	jal ra,sieve
#endif

#ifdef ENABLE_MULTST
	/* 调用 multest() 验证乘除相关运算。 */
	jal ra,multest
#endif

#ifdef ENABLE_STATS
	/* 调用 stats() 进行统计输出。 */
	jal ra,stats
#endif

	/* 通过内存映射输出口（0x1000_0000）打印 "DONE\n"。 */
	lui a0,0x10000000>>12
	addi a1,zero,'D'
	addi a2,zero,'O'
	addi a3,zero,'N'
	addi a4,zero,'E'
	addi a5,zero,'\n'
	sw a1,0(a0)
	sw a2,0(a0)
	sw a3,0(a0)
	sw a4,0(a0)
	sw a5,0(a0)

	li a0, 0x20000000
	li a1, 123456789
	sw a1,0(a0)

	/*
	 * 演示流程结束。
	 * 通过 ebreak 触发 trap 路径，便于 testbench/模拟器停止并报告完成。
	 */
	ebreak


/* Hard mul functions for multest.c
 **********************************/

hard_mul:
	mul a0, a0, a1
	ret

hard_mulh:
	mulh a0, a0, a1
	ret

hard_mulhsu:
	mulhsu a0, a0, a1
	ret

hard_mulhu:
	mulhu a0, a0, a1
	ret

hard_div:
	div a0, a0, a1
	ret

hard_divu:
	divu a0, a0, a1
	ret

hard_rem:
	rem a0, a0, a1
	ret

hard_remu:
	remu a0, a0, a1
	ret

