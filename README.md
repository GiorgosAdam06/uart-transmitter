# UART Transmitter

A parameterized UART transmitter implemented in SystemVerilog to learn serial communication, baud-rate timing, finite-state-machine design, RTL organization, and hardware verification.

The design accepts an 8-bit parallel data value and transmits it serially using a standard 8-N-1 UART frame.

## Specifications

- Simplex transmit-only UART
- 8 data bits
- No parity
- 1 stop bit
- LSB-first transmission
- Configurable system clock frequency
- Configurable baud rate
- Active-low reset
- Busy status output

Default configuration:

- Clock frequency: 50 MHz
- Baud rate: 115200
- Clocks per UART bit: 434

## Module Interface

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low asynchronous reset |
| `start` | Input | 1 | Starts transmission of `data_in` |
| `data_in` | Input | 8 | Parallel byte to transmit |
| `tx` | Output | 1 | UART serial transmit line |
| `busy` | Output | 1 | High while a frame is being transmitted |

## UART Frame

Each transmission consists of:

```text
Idle | Start | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | Stop
  1  |   0   |                Data                |  1