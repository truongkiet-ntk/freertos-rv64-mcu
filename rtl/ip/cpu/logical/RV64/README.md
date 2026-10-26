# RV64IM72F8SP Core

Tài liệu này ghi lại trạng thái RTL của core tại thời điểm rà soát **26-10-2026**. Nội dung dựa trên mã nguồn và các testbench trong thư mục này; đây không phải tuyên bố về mức độ tuân thủ đặc tả RISC-V hay kết quả tổng hợp FPGA.

## Tổng quan

- Core RTL chính: `modules/RV64IM72F_8SP.v`, module `RV64IM72F8SP`, mặc định `XLEN = 64`.
- Wrapper hệ thống FPGA: `modules/72F8SP_SoC_TOP.v`, module `RV64IM72F8SPSoCTOP`.
- Core nhận clock/reset, trạng thái ngắt timer và external, tín hiệu busy của UART cùng dữ liệu đọc MMIO; xuất instruction đã retire và các tín hiệu địa chỉ/dữ liệu/ghi MMIO.
- Các khối chính gồm bộ giải mã và điều khiển, register file, ALU 32/64-bit, nhân/chia, dự đoán nhánh, forwarding/hazard, các thanh ghi pipeline, bộ nhớ lệnh/dữ liệu, CSR và trap controller.

## Chức năng hiện có trong RTL

- Đường xử lý số nguyên 64-bit; có các đường thao tác word 32-bit và datapath nhân/chia.
- Decoder/control có các nhóm lệnh U/J/branch/load/store/I/R, lệnh word và lệnh system/CSR. Có xử lý `ECALL`, `EBREAK`, `MRET`, lỗi căn chỉnh địa chỉ, timer interrupt và external interrupt.
- CSR machine-mode có các thanh ghi như `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mip`, `mcycle` và `minstret`.
- Core có các ranh giới pipeline IF/IO/ID/EXR/EX/EX2/MEM/WB, điều khiển stall/flush và logic lưu PC tiếp tục khi xử lý ngắt.
- Instruction memory khai báo 8192 từ 32-bit và nạp `modules/firmware_RV64_rheal_up.mem`. Data memory được tổ chức thành 8 bank byte, mỗi bank khai báo 4096 phần tử.
- Wrapper SoC có các khối PS/2, UART, VRAM/video và HDMI. Việc dựng wrapper cần thêm các module/IP của hệ thống FPGA, chẳng hạn clock wizard, I/O buffer và các khối video ngoài thư mục core.

Tên module có `RV64IM` và RTL có datapath cho nhân/chia, nhưng các regression hiện có không đủ để khẳng định tuân thủ đầy đủ một phiên bản ISA cụ thể.

## Kiểm thử đã chạy

Các testbench dưới đây đã được biên dịch/chạy bằng Icarus Verilog trong lần rà soát này:

| Testbench | Phạm vi kiểm tra | Kết quả |
| --- | --- | --- |
| `CSR_File_tb.v` | CSR, trạng thái pending/enable ngắt, cập nhật MIE/MPIE và MRET | PASS |
| `Exception_Detector_tb.v` | Ngoại lệ, căn chỉnh địa chỉ, mask/priority của ngắt | PASS |
| `TrapController_tb.v` | Trap/IRQ entry, drain pipeline, ghi MEPC/MCAUSE, MRET và stall | PASS |
| `External_Interrupt_tb.v` | CSR và trap controller khi có external interrupt | PASS |
| `RV32IM54F_8SP_tb.v` (top `RV64IM72F8SP_Core_tb`) | Core-only external interrupt: cấu hình CSR, lưu `mepc`, vào handler | PASS |

Trong core test, core bật MEIE/MIE, nhận MEIP, lưu `mepc = 0x24`, ghi `mcause = 0x800000000000000b` và thực thi lệnh đầu tiên của handler.

Để chạy regression theo Makefile:

```sh
cd rtl/ip/cpu/logical/RV64
make sim
```

Makefile dùng QuestaSim; có thể đổi đường dẫn cài đặt bằng biến `QUESTA_HOME`. Chạy riêng core test bằng:

```sh
make sim=RV64IM72F8SP_Core_tb
```

## Giới hạn và việc cần xác nhận

- Các test hiện tại là test có mục tiêu, chưa phải bộ kiểm tra tương thích ISA RISC-V đầy đủ; chưa có kết quả tổng hợp, timing hoặc xác nhận chạy trên board trong thư mục này.
- `OPCODE_ATOMIC` được khai báo nhưng chưa thấy đường giải mã/điều khiển thực thi atomic trong core. RTL cũng chưa có đường floating-point; instruction memory và PC hiện xử lý lệnh 32-bit, không thể hiện hỗ trợ compressed instruction.
- Khi nạp firmware, Icarus báo file firmware có ít từ hơn phạm vi `[0:8191]` của instruction memory. Core test hiện ghi đè nội dung bộ nhớ trước khi chạy; cần kiểm tra độ đầy đủ của image và hành vi khởi động firmware thực tế.
- Wrapper SoC phụ thuộc các IP/module FPGA ngoài thư mục này; riêng core testbench dùng mô hình MMIO/CLINT, không thay thế kiểm thử tích hợp toàn SoC.

**Đánh giá hiện tại:** core có các khối thực thi và xử lý trap/interrupt tương đối hoàn chỉnh ở mức RTL; các luồng CSR và external interrupt đã qua regression hướng mục tiêu. Nên xem đây là trạng thái đang phát triển, chưa có bằng chứng trong repo cho mức sẵn sàng phát hành hoặc tuân thủ ISA đầy đủ.
