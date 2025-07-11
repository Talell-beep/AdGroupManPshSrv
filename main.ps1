param()

#Main executable to be run as a service to query the DB and then carry out the needed actions on AD
function Start-Checks {
    Set-Location $PSScriptRoot #Set working directory to a controlled area
    try {
        Import-Module -Name "PSSQLite"
        Import-Module -Name "ActiveDirectory"
    } catch {
        $ErrorOut = Get-Module -ListAvailable | Select-Object Name,Version
        throw "Required module missing, check installation of PSSQLite and RSAT Active Directory"
        Write-Verbose "Available Modules:"
        Write-Verbose $ErrorOut
    }

    $db = ".\data.db"
    if ( -not ( Test-Path -Path $db -ErrorAction SilentlyContinue ) ) {
        Write-Verbose "No database file found, creating"

        $SetupTableIn = 'CREATE TABLE IF NOT EXISTS "In" ( "Id"	INTEGER NOT NULL UNIQUE, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL);'
        .\sqlite3.exe data.db $SetupTableIn
        $SetupTableDone = 'CREATE TABLE IF NOT EXISTS "Success" ( "Id"	INTEGER NOT NULL UNIQUE, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "Output"	INTEGER NOT NULL);'
        .\sqlite3.exe data.db $SetupTableDone
        $SetupTableError = 'CREATE TABLE IF NOT EXISTS "Error" ( "Id"	INTEGER NOT NULL, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "Output"	TEXT );'
        .\sqlite3.exe data.db $SetupTableError
        $SetupTablePackages = 'CREATE TABLE IF NOTE EXISTS "Packages" ( "Id"	INTEGER NOT NULL UNIQUE, "Name"	TEXT NOT NULL, "Method"	TEXT NOT NULL, "Assignment"	TEXT NOT NULL, PRIMARY KEY("Id" AUTOINCREMENT));'
        .\sqlite3.exe data.db $SetupTablePackages
    }

    #Check if packages file exists
    Write-Verbose "Checking Packages.csv"
    if ( -not ( Test-Path .\Packages.csv ) ) { throw "No Packages.csv in programs root directory. This must be supplied"}
    $TestPackagesCsv = Import-Csv -Path ".\Packages.csv"
    if ( $null -eq $TestPackagesCsv.Name -or $null -eq $TestPackagesCsv.Group -or $null -eq $TestPackagesCsv.Method ) { throw "Invalid Packages.csv, review content" }

    #Create the SQL query to bulk input the packages data into the db, this should happen every time the service is started
    $ImportTablePackagesData = "BEGIN TRANSACTION;"
    for ($i = 0;$i -lt $TestPackagesCsv.Count;$i++) {$ImportTablePackagesData = $ImportTablePackagesData + " INSERT INTO 'Packages' ('Name','Method','Assignment') VALUES ('$($TestPackagesCsv[$i].Name)','$($TestPackagesCsv[$i].Method)','$($TestPackagesCsv[$i].Assignment)');"}
    $ImportTablePackagesData = $ImportTablePackagesData + "COMMIT;"

    #Import the horrible mess I have generated
    .\sqlite3.exe data.db $ImportTablePackagesData
}