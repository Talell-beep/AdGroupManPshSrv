param()

#Main executable to be run as a service to query the DB and then carry out the needed actions on AD
function Start-Checks {
    Set-Location $PSScriptRoot #Set working directory to a controlled area
    try {
        Import-Module -Name "PSSQLite"
        Import-Module -Name "ActiveDirectory"
    } catch {
        $ErrorOut = Get-Module -ListAvailable | Select-Object Name,Version
        Write-Verbose "Available Modules:"
        Write-Verbose $ErrorOut
        throw "Required module missing, check installation of PSSQLite and RSAT Active Directory"
    }

    $script:db = ".\data6.db"

    if ( -not ( Test-Path -Path $script:db -ErrorAction SilentlyContinue ) ) {
        Write-Verbose "No database file found, creating"

        #Make the basic structure of the DB if it does not exist.
        $SetupTransaction = 'BEGIN TRANSACTION;
        CREATE TABLE IF NOT EXISTS "In" ( "Id"	INTEGER NOT NULL UNIQUE, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, PRIMARY KEY("Id" AUTOINCREMENT));
        CREATE TABLE IF NOT EXISTS "Success" ( "Id"	INTEGER NOT NULL UNIQUE, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "Output"	TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS "Error" ( "Id"	INTEGER NOT NULL, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "Output"	TEXT );
        COMMIT;'
        .\sqlite3.exe $script:db $SetupTransaction
    }

    #Check if packages file exists
    Write-Verbose "Checking Packages.csv"
    if ( -not ( Test-Path .\Packages.csv ) ) { throw "No Packages.csv in programs root directory. This must be supplied"}
    $TestPackagesCsv = Import-Csv -Path ".\Packages.csv"
    if ( $null -eq $TestPackagesCsv.Name -or $null -eq $TestPackagesCsv.Group -or $null -eq $TestPackagesCsv.Method ) { throw "Invalid Packages.csv, review content" }

    #Create the SQL query to bulk input the packages data into the db, this should happen every time the service is started
    #Drop packages table to cleanly have a fresh table to ingest the packages.csv into
    $ImportTablePackagesData = 'BEGIN TRANSACTION;
    DROP TABLE IF EXISTS Packages;
    CREATE TABLE IF NOT EXISTS "Packages" ( "Id"	INTEGER NOT NULL UNIQUE, "Name"	TEXT NOT NULL, "Method"	TEXT NOT NULL, "Assignment"	TEXT NOT NULL, PRIMARY KEY("Id" AUTOINCREMENT));'
    #Loops through each line in the csv and creates the insert statement to use in the transaction
    for ($i = 0;$i -lt $TestPackagesCsv.Count;$i++) {
        $ImportTablePackagesData = $ImportTablePackagesData + " INSERT INTO 'Packages' ('Name','Method','Assignment') VALUES ('$($TestPackagesCsv[$i].Name -replace '[\W]','')','$($TestPackagesCsv[$i].Method -replace '[\W]','')','$($TestPackagesCsv[$i].Assignment -replace '[\W]','')');"
    }
    $ImportTablePackagesData = $ImportTablePackagesData + "COMMIT;"

    #Import the horrible mess I have generated
    .\sqlite3.exe $script:db $ImportTablePackagesData
}

function Invoke-Runtime {
    for (;;) {
        Start-Sleep -seconds 10 #Don't want this running permanently eating up all resources, hard set to 10s right now for testing, planned to allow configuration
        
        $GetTableIn = ''
    }
}

Start-Checks