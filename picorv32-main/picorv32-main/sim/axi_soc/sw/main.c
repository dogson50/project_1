#include <stdint.h>

#define DMA_BASE          0x40000000u
#define DMA_CTRL          (*(volatile uint32_t *)(DMA_BASE + 0x00u))
#define DMA_STATUS        (*(volatile uint32_t *)(DMA_BASE + 0x04u))
#define DMA_SRC_ADDR      (*(volatile uint32_t *)(DMA_BASE + 0x08u))
#define DMA_DST_ADDR      (*(volatile uint32_t *)(DMA_BASE + 0x0Cu))
#define DMA_BYTE_LEN      (*(volatile uint32_t *)(DMA_BASE + 0x10u))
#define DMA_ERR_CODE      (*(volatile uint32_t *)(DMA_BASE + 0x14u))
#define DMA_PERF_CYCLE    (*(volatile uint32_t *)(DMA_BASE + 0x18u))
#define DMA_PERF_RDWORDS  (*(volatile uint32_t *)(DMA_BASE + 0x1Cu))
#define DMA_PERF_WRWORDS  (*(volatile uint32_t *)(DMA_BASE + 0x20u))
#define DMA_BURST_WORDS   (*(volatile uint32_t *)(DMA_BASE + 0x24u))

#define DMA_CTRL_START       (1u << 0)
#define DMA_CTRL_SOFT_RESET  (1u << 1)
#define DMA_CTRL_IRQ_EN      (1u << 2)

#define DMA_STATUS_BUSY      (1u << 0)
#define DMA_STATUS_DONE      (1u << 1)
#define DMA_STATUS_ERROR     (1u << 2)
#define DMA_STATUS_IRQ_PEND  (1u << 3)

static volatile uint32_t * const data_mem = (volatile uint32_t *)0x20000000u;
static volatile uint32_t * const src_buf  = (volatile uint32_t *)0x20000100u;
static volatile uint32_t * const dst_buf  = (volatile uint32_t *)0x20000200u;

static void dma_clear_status(void)
{
    DMA_STATUS = (DMA_STATUS_DONE | DMA_STATUS_ERROR | DMA_STATUS_IRQ_PEND);
}

int main(void)
{
    uint32_t i;
    uint32_t ok = 1u;
    uint32_t status = 0u;
    uint32_t timeout = 0u;
    const uint32_t words = 256u;
    const uint32_t bytes = words * 4u;

    for (i = 0; i < words; i++) {
        src_buf[i] = 0x1000u + i * 3u;
        dst_buf[i] = 0u;
    }

    DMA_CTRL = DMA_CTRL_SOFT_RESET;
    dma_clear_status();

    DMA_SRC_ADDR = (uint32_t)src_buf;
    DMA_DST_ADDR = (uint32_t)dst_buf;
    DMA_BYTE_LEN = bytes;
    DMA_BURST_WORDS = 64u;

    DMA_CTRL = DMA_CTRL_START | DMA_CTRL_IRQ_EN;

    for (timeout = 0; timeout < 100000u; timeout++) {
        status = DMA_STATUS;
        if ((status & DMA_STATUS_DONE) != 0u) {
            break;
        }
        if ((status & DMA_STATUS_ERROR) != 0u) {
            ok = 0u;
            break;
        }
    }

    if (timeout == 100000u) {
        ok = 0u;
    }

    if ((status & DMA_STATUS_DONE) == 0u) {
        ok = 0u;
    }

    for (i = 0; i < words; i++) {
        if (dst_buf[i] != src_buf[i]) {
            ok = 0u;
            break;
        }
    }

    // Keep debug breadcrumbs for waveform and memory inspection.
    data_mem[1] = DMA_STATUS;
    data_mem[2] = DMA_ERR_CODE;
    data_mem[3] = DMA_PERF_CYCLE;
    data_mem[4] = DMA_PERF_RDWORDS;
    data_mem[5] = DMA_PERF_WRWORDS;
    if (DMA_PERF_CYCLE != 0u) {
        data_mem[6] = ((DMA_PERF_RDWORDS + DMA_PERF_WRWORDS) * 100u) / DMA_PERF_CYCLE;
    } else {
        data_mem[6] = 0u;
    }

    // Existing testbench checks data_mem[0] == 12 for PASS.
    data_mem[0] = ok ? 12u : 0xDEAD0001u;

    __asm__ volatile ("ebreak");
    while (1) {
        __asm__ volatile ("nop");
    }
}
