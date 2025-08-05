```mermaid
graph TD
    subgraph "Start & Initialization"
        A[Start] --> B{Load ConfigFile?};
        B --> C[Process Parameters];
        C --> D{Validate Parameters};
        D --> E{"dirty.txt exists?"};
        E -- Yes --> F[Run Cleanup Routine];
        F --> G["Create new dirty.txt"];
        E -- No --> G;
    end

    G --> H{"-InstallDrivers or -CopyDrivers?"};

    subgraph "Pre-Build Preparations"
        H -- Yes --> I{Driver Source?};
        I -- "-DriversJsonPath" --> J[Download Drivers via JSON in Parallel];
        I -- "-Make and -Model" --> K[Download Drivers for specific Make/Model];
        I -- "Local Folder" --> L[Use Existing Drivers in Drivers Folder];
        
        subgraph "ADK & WinPE"
            M[Check for ADK & WinPE Add-on];
            M --> N{Latest Version Installed?};
            N -- No --> O[Uninstall Old & Install Latest ADK/WinPE];
            N -- Yes --> P[Get ADK Path];
            O --> P;
        end

        Q{"-InstallApps?"};
        subgraph "Application & In-VM Content Preparation"
            direction LR
            R[Check for existing downloaded apps];
            R --> S{Download missing WinGet apps};
            S --> T{"-InstallOffice?"};
            T -- Yes --> U[Download ODT & Office content];
            T -- No --> V[Continue];
            U --> V;
            V --> W["Download in-VM updates: Defender, MSRT, etc."];
            W --> X["Create Apps.iso"];
        end
    end

    J --> M;
    K --> M;
    L --> M;
    H -- No --> M;
    P --> Q;
    Q -- Yes --> R;
    X --> Y;
    Q -- No --> Y{"-AllowVHDXCaching?"};

    subgraph "VHDX Management"
        Y -- Yes --> Z[Check for matching cached VHDX];
        Z --> AA{Cache Hit?};
        AA -- Yes --> AB[Use Cached VHDX];
        AA -- No --> AC[Create New VHDX];
        Y -- No --> AC;

        subgraph "VHDX Creation Workflow"
            AC --> AD{ISOPath provided?};
            AD -- No --> AE[Download Windows ESD media];
            AD -- Yes --> AF[Use provided ISO];
            AE --> AG[Create & Partition VHDX];
            AF --> AG;
            AG --> AH[Apply Base Windows Image to VHDX];
            AH --> AI{"Updates specified? (CU, dotNET, etc.)"};
            AI -- Yes --> AJ[Apply Updates to Offline VHDX];
            AJ --> AK[Run Component Cleanup];
            AI -- No --> AK;
            AK --> AL{"Optional Features specified?"};
            AL -- Yes --> AM[Enable Optional Features];
            AL -- No --> AN[Finalize VHDX Setup];
            AM --> AN;
            AN --> AO{"-AllowVHDXCaching?"};
            AO -- Yes --> AP[Optimize and Copy VHDX to Cache];
            AO -- No --> AQ[Continue];
            AP --> AQ;
        end
    end
    
    AB --> BA;
    AQ --> BA{"-InstallApps?"};

    subgraph "FFU Creation"
        subgraph "VM-Based Capture (-InstallApps)"
            direction LR
            BB[Create Hyper-V VM from VHDX];
            BB --> BC["Create WinPE Capture Media iso"];
            BC --> BD[Configure network share for capture];
            BD --> BE["Start VM: Boots to Audit Mode"];
            BE --> BF[Orchestrator runs: Installs apps, syspreps, shuts down];
            BF --> BG[VM reboots from Capture Media];
            BG --> BH["CaptureFFU.ps1 runs, saves FFU to share, shuts down"];
        end

        subgraph "Direct VHDX Capture"
            BI[Capture FFU directly from VHDX using DISM];
        end
    end
    
    BA -- Yes --> BB;
    BA -- No --> BI;

    subgraph "Post-Processing & Media Creation"
        BK{"-InstallDrivers?"};
        BK -- Yes --> BL[Mount FFU & Inject Drivers];
        BK -- No --> BM[Continue];
        BL --> BM;
        BM --> BN{"-Optimize?"};
        BN -- Yes --> BO[Optimize FFU using DISM];
        BN -- No --> BP[Continue];
        BO --> BP;
        BP --> BQ{"-BuildUSBDrive?"};
        BQ -- Yes --> BR[Create WinPE Deployment Media];
        BR --> BS["Partition USB Drive(s)"];
        BS --> BT[Copy FFU, Deploy scripts & other assets to USB];
        BQ -- No --> BU[Continue];
        BT --> BU;
    end

    BH --> BK;
    BI --> BK;

    subgraph "Final Cleanup"
        BU --> BV[Cleanup VM, VHDX, temp files];
        BV --> BW["Remove dirty.txt"];
        BW --> BX[End];
    end