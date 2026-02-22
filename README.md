# Custom-DMA-engine-Avalon-MM-to-Avalon-ST
# Avalon-MM to Avalon-ST DMA Engine & Bridge

🥈 **Awarded 2nd Prize at the VLSI Hackathon**

##  Overview
This repository contains the RTL design and verification of a custom Direct Memory Access (DMA) engine designed for Intel FPGAs. The core function of this IP is to bridge the Memory-Mapped (Avalon-MM) and Streaming (Avalon-ST) domains. 

The system reads data from On-Chip SRAM using a custom Finite State Machine (FSM) acting as an Avalon-MM Master, and streams that data to a downstream consumer via an Avalon-ST Source interface.

##  System Architecture

The architecture decouples the memory fetch plane from the data consumption plane, ensuring high system stability even under heavy backpressure from slow peripherals.

```mermaid
graph TD
    subgraph "FPGA Fabric"
    
        subgraph "Custom DMA Engine (Master)"
            FSM[4-State FSM] -- "Avalon-MM Read" --> B[Address Gen]
            B -- "Bypass/Extract" --> C[Data Output Buffer]
        end
        
        subgraph "Platform Designer (Qsys) Subsystem"
            B -- "Address (16-bit)" --> Bridge[Avalon-MM Bridge]
            Bridge --> RAM[On-Chip SRAM]
        end
        
        subgraph "Downstream Consumer (Slave)"
            C -- "Avalon-ST (Data, Valid, Ready)" --> Throttle[Backpressure Logic]
            Throttle --> LED[Output Latch / LEDs]
        end
    
    end
