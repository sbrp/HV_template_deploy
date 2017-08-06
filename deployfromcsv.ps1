# CSV to read settings from
#$VirtualMachinesCSV = Read-Host "Enter path to CSV file containing settings"
$VirtualMachinesCSV = "$PSScriptRoot\test_spec1.csv"
# Get settings from CSV
$vmdetails = Import-Csv $VirtualMachinesCSV
#define the source of the unattend xml
$unattendxmlsource = "$PSScriptRoot\unattend.xml"
#define the path the vms will be held in
$vmpath = "c:\vms"
#define the source of the sysprepped vhdx 
$sourcevhd = "$vmpath\_templates\sysprepped.vhdx"

# Start the foreach loop
$vmdetails|ForEach-Object {

    # VM Name
    $VMName = $_.vmname
    #define the destination of the unattend xml
    $unattendxmldest = "$vmpath\$vmname\unattend.xml"
    #define the target of the sysprepped vhdx
    $targetvhd = "$vmpath\$vmname\$vmname-1.vhdx"
    # Automatic Start Action (Nothing = 0, Start =1, StartifRunning = 2)
    $AutoStartAction = 2
    # In second
    $AutoStartDelay = 0
    # Automatic Stop Action (TurnOff = 0, Save =1, Shutdown = 2)
    $AutoStopAction = 2


    ###### Hardware Configuration ######


    # VM Generation (1 or 2)
    $Gen = 2

    # Processor Number
    $ProcessorCount = $_.NumVCPU

    ## Memory (Static = 0 or Dynamic = 1)
    $Memory = 1
    # StaticMemory
    $StaticMemory = 4GB

    # DynamicMemory
    $StartupMemory = ([int]($_.StartupMemoryGB) * 1GB)
    $MinMemory = ([int]($_.MinMemoryGB) * 1GB)
    $MaxMemory = ([int]($_.MaxMemoryGB) * 1GB)

    ### Additional virtual drives - will only get added if a correct value higher than 0 is added in the CSV
    # bad or empty entries are ignored
    $ExtraDrive = @()

    # Drive 2
    if ($_.Disk2SizeGB -gt 0) {
        $Drive = New-Object System.Object
        $Drive       | Add-Member -MemberType NoteProperty -Name Name -Value "$VMName-2"
        $Drive       | Add-Member -MemberType NoteProperty -Name Path -Value $($VMPath + "\" + $VMName)
        $Drive       | Add-Member -MemberType NoteProperty -Name Size -Value ([int]($_.Disk2SizeGB) * 1GB)
        $Drive       | Add-Member -MemberType NoteProperty -Name Type -Value Dynamic
        $ExtraDrive += $Drive
    }

    # Drive 3
    if ($_.Disk3SizeGB -gt 0) {
        $Drive = New-Object System.Object
        $Drive       | Add-Member -MemberType NoteProperty -Name Name -Value "$VMName-3"
        $Drive       | Add-Member -MemberType NoteProperty -Name Path -Value $($VMPath + "\" + $VMName)
        $Drive       | Add-Member -MemberType NoteProperty -Name Size -Value ([int]($_.Disk3SizeGB) * 1GB)
        $Drive       | Add-Member -MemberType NoteProperty -Name Type -Value Dynamic
        $ExtraDrive += $Drive
    }

    # Drive 4
    if ($_.Disk4SizeGB -gt 0) {
        $Drive = New-Object System.Object
        $Drive       | Add-Member -MemberType NoteProperty -Name Name -Value "$VMName-4"
        $Drive       | Add-Member -MemberType NoteProperty -Name Path -Value $($VMPath + "\" + $VMName)
        $Drive       | Add-Member -MemberType NoteProperty -Name Size -Value ([int]($_.Disk4SizeGB) * 1GB)
        $Drive       | Add-Member -MemberType NoteProperty -Name Type -Value Dynamic
        $ExtraDrive += $Drive
    }
    # You can copy/delete this below block as you wish to create (or not) and attach several VHDX

    ### Network Adapters
    # Primary Network interface: VMSwitch 
    $VMSwitchName = (Get-VMSwitch | Where {$_.Name -notlike "*legacy*"}).name

    ## Additional NICs
    $NICs = @()


    ######################################################
    ###           VM Creation and Configuration        ###
    ######################################################

    ## Creation of the VM
    # Creation without VHD and with a default memory value (will be changed after)
    New-VM -Name $VMName `
        -Path $VMPath `
        -NoVHD `
        -Generation $Gen `
        -MemoryStartupBytes 1GB `
        -SwitchName $VMSwitchName


    if ($AutoStartAction -eq 0) {$StartAction = "Nothing"}
    Elseif ($AutoStartAction -eq 1) {$StartAction = "Start"}
    Else {$StartAction = "StartIfRunning"}

    if ($AutoStopAction -eq 0) {$StopAction = "TurnOff"}
    Elseif ($AutoStopAction -eq 1) {$StopAction = "Save"}
    Else {$StopAction = "Shutdown"}

    ## Changing the number of processor and the memory
    # If Static Memory
    if (!$Memory) {
        Set-VM -Name $VMName `
            -ProcessorCount $ProcessorCount `
            -StaticMemory `
            -MemoryStartupBytes $StaticMemory `
            -AutomaticStartAction $StartAction `
            -AutomaticStartDelay $AutoStartDelay `
            -AutomaticStopAction $StopAction


    }
    # If Dynamic Memory
    Else {
        Set-VM -Name $VMName `
            -ProcessorCount $ProcessorCount `
            -DynamicMemory `
            -MemoryMinimumBytes $MinMemory `
            -MemoryStartupBytes $StartupMemory `
            -MemoryMaximumBytes $MaxMemory `
            -AutomaticStartAction $StartAction `
            -AutomaticStartDelay $AutoStartDelay `
            -AutomaticStopAction $StopAction

    }


    # Attach each Disk in the collection
    #copy the vhdx to the relevant vm location
    Copy-item $sourcevhd -Destination $targetvhd

    #copy the unattend xml to the destination so it can be modified for the particular vm
    Copy-item "$unattendxmlsource" -Destination "$unattendxmldest"

    #do a find and replace on the defined string so that the computername is saved in the unattend.xml file
    (Get-Content $unattendxmldest).replace("DSC_COMPUTERNAME", "$vmname") | Set-Content "$unattendxmldest"

    #mount the vhdx
    Mount-VHD $targetvhd

    #get the drive letter for the mounted vhdx file
    $driveletter = [string]((Get-DiskImage $targetvhd | get-disk | get-partition| Where-Object -Property type -EQ "basic").Driveletter) + ":"

    #copy the unattend.xml to the relevant folder inside the vhdx file
    Copy-Item $unattendxmldest -Destination $driveletter\Windows\Panther\

    #unmount the vhdx
    Dismount-VHD $targetvhd

    #attach the vhdx file to vm
    Add-VMHardDiskDrive -vmname $vmname -Path $targetvhd

    Foreach ($Disk in $ExtraDrive) {
        # if it is dynamic
        if ($Disk.Type -like "Dynamic") {
            New-VHD -Path $($Disk.Path + "\" + $Disk.Name + ".vhdx") `
                -SizeBytes $Disk.Size `
                -Dynamic
        }
        # if it is fixed
        Elseif ($Disk.Type -like "Fixed") {
            New-VHD -Path $($Disk.Path + "\" + $Disk.Name + ".vhdx") `
                -SizeBytes $Disk.Size `
                -Fixed
        }

        # Attach the VHD(x) to the Vm
        Add-VMHardDiskDrive -VMName $VMName `
            -Path $($Disk.Path + "\" + $Disk.Name + ".vhdx")
    }



    #Get the first HDD in list
    $OsVirtualDrive = Get-VMHardDiskDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 0
     
    # Set the boot order, disable secureboot
    Set-VMFirmware -VMName $VMName -BootOrder $OsVirtualDrive -EnableSecureBoot Off

    #start the vm
    Start-VM -Name $vmname

}