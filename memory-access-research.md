# Memory Access Architecture Research: Pixel 8 Pro (Exynos 2400/Zuma)

## Overview
The Pixel 8 Pro uses a complex multi-layered memory system with:
- Physical DRAM (0x00 - 0xFFF...FFF)
- IOMMU translation (SYSMMU)
- Reserved memory regions
- DMA memory pools
- Secure/TEE memory
- Device-specific memory windows

---

## 1. Physical Memory Map

### Main DRAM Address Space
```
0x0000_0000 - 0x0FFF_FFFF  : First 256MB (typically kernel/system)
0x1000_0000 - 0xFDFF_FFFF  : Main DRAM (expandable)
0xFD80_0000 - 0xFDFF_FFFF  : Bootloader Log & High Memory
0xfd3f_0000 - 0xfdff_ffff  : Reserved Regions (ramoops, debug)
```

### Platform-Specific Regions
```
0x90000000 - 0x905FFFFF    : ECT Binary, GSA Firmware
0x91000000 - 0x9FFFFFFF    : GPU/AI Accelerator Memory
0x94000000 - 0x96FFFFFF    : AOC (Always-On Coprocessor)
0x97000000 - 0x97400000    : xHCI DMA DRAM
0xC3000000 - 0xC3090000    : Seclog (Secure Logging)
0xD8100000 - 0xDDA20000    : Logging/Debug Memory
0xE8000000 - 0xF6200000    : Modem/CP Memory
0xF8800000 - 0xFAFFFFFF    : ABL (Bootloader)
0xFD3FF000 - 0xFD7FFFFF    : Ramoops/Performance Info
```

---

## 2. Reserved Memory Structure (from DTB)

### System Reserved Regions

```
ect_binary
  Address: 0x90000000
  Size:    0x60000 (384 KB)
  Purpose: Early CPU Topology info
  Access:  Kernel bootup

gsa (Global Security Agent)
  Address: 0x90200000
  Size:    0x3FF000 (4 MB)
  Purpose: Security operations, hardware security
  Access:  Trusty TEE, Kernel

gxp_fw (Google Tensor Accelerator)
  Address: 0x91D00000
  Size:    0x300000 (3 MB)
  Purpose: AI/ML accelerator firmware
  Access:  GXP driver

tpu_fw (Tensor Processing Unit)
  Address: 0x93000000
  Size:    0x1000000 (16 MB)
  Purpose: TPU firmware for ML workloads
  Access:  TPU driver

aoc (Always-On Coprocessor)
  Address: 0x94000000
  Size:    0x3000000 (48 MB)
  Purpose: Always-on sensors, audio processing
  Access:  Audio/sensor drivers
```

### DMA Memory Pools

```
video_stream (vstream)
  Size:    0x4800000 (72 MB)
  Reusable: Yes (shared-dma-pool)
  Alignment: 64KB
  Protected: Yes (dma-heap)
  Use: Video streaming/encoding

video_frame (vframe)
  Size:    0x20000000 (512 MB)
  Protected: Yes
  Alignment: 64KB
  Use: Frame buffers for video

video_scaler (vscaler)
  Size:    0x3400000 (52 MB)
  Protected: Yes
  Use: Scaling/transform operations

tui (Trusted UI)
  Size:    0x1800000 (24 MB)
  Protected: Yes
  Use: Secure display content

faceauth_dsp
  Size:    0x2000000 (32 MB)
  Protected: Yes
  Use: Face authentication DSP

faceauth_tpu
  Size:    0x1000000 (16 MB)
  Protected: Yes
  Use: Face recognition ML
```

---

## 3. Memory Access Layers

### Layer 1: CPU Direct Access (No Translation)
```
Virtual Address → Physical Address (1:1 mapping)
CPU Registers (Cortex-A78/A76)
  ├─ MMU disabled/paging off → Direct physical access
  ├─ Coherent memory operations
  └─ Full address space accessible
```

### Layer 2: IOMMU Translation (SYSMMU)
For peripherals that need virtualized memory:

```
Peripheral Request → SYSMMU MMU → Physical Address

  └─ samsung-sysmmu (Exynos System MMU)
     ├─ Groups devices (USB, UFS, etc)
     ├─ Provides isolation
     └─ Translates via page tables
```

### Layer 3: DMA Coherency Management

```
DMA Operation Request
  ├─ DMA Coherent (CPU-DMA synchronized)
  │  └─ No cache flush needed, shared L3/system cache
  ├─ DMA Non-Coherent
  │  └─ Requires explicit cache invalidation
  └─ Memory Region specifies dma-coherent property
```

### Layer 4: Protected Memory Allocator

```
ARM Physical Memory Group Manager + Protected Memory Allocator
  ├─ Manages protection IDs
  ├─ Enforces access control to secure regions
  ├─ Protection ID 0x00 = Normal
  ├─ Protection ID 0x0F+ = TEE/Secure
  └─ Hardware SmartMCU monitors access
```

---

## 4. IOMMU/SYSMMU System

### SYSMMU Instances

```
PCIe SYSMMU @ 0x12060000 (PCIe_CH0)
  - Port: PCIe_CH0
  - HSI Block: 1
  - Status: Currently DISABLED
  - QoS: 0x0F

PCIe SYSMMU @ 0x131C0000 (PCIe_CH1)
  - Port: PCIe_CH1
  - HSI Block: 2
  - Status: Currently DISABLED
  - QoS: 0x0F

GXP IOMMU (for AI accelerator)
  - Window: 0x1000_0000 - 0x0FFF_FFFF (16GB virtual)
  - Reserved: 0x80000000 (pages)
  - PASID bits: 3
```

### SYSMMU Group Configuration

```
samsung,sysmmu-group
  ├─ transparent = true/false
  ├─ use-map-once = true/false
  ├─ qos-level = 0x0F (max priority)
  └─ port-name identifies peripheral
```

---

## 5. DMA Access Patterns

### Pattern A: Contiguous DMA Buffer
```c
// Allocate from dma-heap (e.g., vframe)
buf = dma_alloc_coherent(dev, size, &phys_addr, GFP_KERNEL);

// Device sees physical address directly
// CPU accesses via virtual mapping
```

### Pattern B: Scatter-Gather DMA
```c
// Multiple physical regions chained
struct scatterlist *sg;

// IOMMU translates each SG entry
// Device: Linear virtual address space
// Physical: Fragmented real pages
```

### Pattern C: Secure DMA (Protection ID)
```c
// Allocated with protection_id = 0x0F (Secure)
// Hardware enforces: only TEE can access
// Violation → System fault
```

---

## 6. Memory Access Flow - From Boot to Runtime

### Stage 1: Bootloader (ABL)
```
Memory Usage: 0xF8800000 - 0xFAFFFFFF (reserved)
  ├─ MMU disabled initially
  ├─ Direct physical addressing
  └─ Sets up initial page tables
```

### Stage 2: Kernel Boot
```
DTB Parsed → Reserved Regions Marked
  ├─ ect_binary loaded
  ├─ ramoops configured
  └─ DMA coherent pools mapped
```

### Stage 3: Driver Initialization
```
Device Drivers Initialize
  ├─ USB Controller
  │  └─ Allocates xHCI DMA buffers
  ├─ Cameras
  │  └─ Allocate video_frame pools
  ├─ GXP (AI)
  │  └─ Maps with protection_id
  └─ Audio (AOC)
     └─ Uses pre-allocated aoc region
```

### Stage 4: Runtime Access
```
Application → Virtual Address
  ├─ iommu_map() registers page table entries
  ├─ Device makes transfer request
  └─ IOMMU: Virtual → Physical lookup
```

---

## 7. Cache Coherency

### Coherent Regions
```xml
<dma-device>
  dma-coherent;  <!-- CPU cache automatically synchronized -->
  memory-region = <pool>;
</dma-device>
```

### Non-Coherent Access Pattern
```c
// Before DMA write by device:
dma_sync_single_for_device(phys_addr, size, DMA_TO_DEVICE);

// After DMA write by device:
dma_sync_single_for_cpu(phys_addr, size, DMA_FROM_DEVICE);
```

---

## 8. Bare Metal Memory Access Strategy

### For Custom DTB Implementation

#### Step 1: Minimum Required Regions
```dts
reserved-memory {
  #address-cells = <0x02>;
  #size-cells = <0x01>;
  ranges;

  // Essential: kernel/apps
  // DRAM will be auto-detected

  ramoops_mem@fd3ff000 {
    compatible = "ramoops";
    reg = <0x00 0xfd3ff000 0x400000>;
  };
};
```

#### Step 2: DMA Pool Setup (if needed)
```dts
// Only if running drivers that need preallocation
dma_pool {
  compatible = "shared-dma-pool";
  reusable;
  size = <0x10000000>;  // 256MB
  alignment = <0x00 0x1000>;
};
```

#### Step 3: Device Memory Registration
```dts
usb@11210000 {
  // Register for DMA without IOMMU
  memory-region = <&dma_pool>;
};
```

---

## 9. Key Differences: Android vs Bare Metal

| Aspect | Android | Bare Metal |
|--------|---------|-----------|
| IOMMU | Full SYSMMU usage | Optional/simplified |
| Protected Mem | Protection IDs enforced | Ignored if TEE disabled |
| DMA Pools | Pre-allocated, managed | Can be dynamic |
| Cache Coherency | Strictly maintained | Simplified for SoC |
| Memory Layout | Fragmented via dynamic partitions | Linear/contiguous |

---

## 10. Direct Memory Access Without Drivers

### Raw Approach (Dangerous)
```c
// Physical address direct access
volatile uint32_t *reg = (uint32_t *)(0x11210000);  // USB base
*reg = 0xDEADBEEF;  // Direct write

// This works in bare metal WITHOUT:
// - IOMMU translation
// - Permission checking
// - Driver abstraction
```

### Safe Approach (Mapped)
```c
// Virtual memory mapping first
void *virt = phys_to_virt(0x11210000);  // or ioremap()
volatile uint32_t *reg = (uint32_t *)virt;
*reg = 0xDEADBEEF;
```

---

## 11. Memory Debugging & Inspection

### From Kernel
```bash
$ cat /proc/iomem          # Physical memory map
$ cat /proc/meminfo        # Memory usage
$ cat /sys/kernel/debug/iommu/  # IOMMU stats
$ dmesg | grep -i memory   # Boot logs
```

### From DTB Analysis
```bash
$ hexdump -C bare-metal-zuma.dtb
$ dtc -I dtb -O dts < bare-metal-zuma.dtb | grep -A5 memory-region
```

---

## 12. Implementation Checklist for Bare Metal

- [ ] Identify usable DRAM range (typically 0x0 to bootloader base)
- [ ] Reserve critical regions (ramoops, ECT if needed)
- [ ] Define DMA pools for peripherals (USB, UFS)
- [ ] Mark dma-coherent devices
- [ ] Include IOMMU nodes if devices use virtual addressing
- [ ] Set correct protection IDs for secure regions
- [ ] Test memory access patterns (read/write/DMA)
- [ ] Verify no bootloader/firmware collisions

---

## References in DTB

- **Reserved Memory**: Lines 27-350 (first 300 lines contain all allocations)
- **GXP IOMMU**: Line 11498+ (callisto@20C00000)
- **PCIe SYSMMU**: Lines 11447, 11498
- **Boot Memory**: Lines 20-30 (bootloader_log, ect_binary)
- **Trusty Regions**: Lines 505-550 (dma-heaps under trusty node)