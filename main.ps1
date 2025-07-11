param()

#Main executable to be run as a service to query the DB and then carry out the needed actions on AD
function Start-Checks {
    Set-Location $PSScriptRoot #Set working directory to a controlled area
    try {
        Import-Module -Name "PSSQLite"
        #Import-Module -Name "ActiveDirectory"
    } catch {
        $ErrorOut = Get-Module -ListAvailable | Select-Object Name,Version
        Write-Verbose "Available Modules:"
        Write-Verbose $ErrorOut
        throw "Required module missing, check installation of PSSQLite and RSAT Active Directory"
    }

    $script:db = ".\data.db"

    if ( -not ( Test-Path -Path $script:db -ErrorAction SilentlyContinue ) ) {
        Write-Verbose "No database file found, creating"

        #Make the basic structure of the DB if it does not exist.
        $SetupTransaction = 'BEGIN TRANSACTION;
        CREATE TABLE IF NOT EXISTS "In" ( "Id"	INTEGER NOT NULL UNIQUE, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "DateCreated"	TEXT NOT NULL, PRIMARY KEY("Id" AUTOINCREMENT));
        CREATE TABLE IF NOT EXISTS "Success" ( "Id"	INTEGER NOT NULL UNIQUE, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "DateCreated"	TEXT NOT NULL, "DateActioned"	TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS "Error" ( "Id"	INTEGER NOT NULL, "Device"	TEXT NOT NULL, "Package"	TEXT NOT NULL, "TaskRef"	TEXT NOT NULL, "Output"	TEXT, "DateCreated"	TEXT NOT NULL, "DateActioned"	TEXT NOT NULL);
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
        #This could probably be neater but oh well
        $ImportTablePackagesData = $ImportTablePackagesData + " INSERT INTO 'Packages' ('Name','Method','Assignment') VALUES ('$($TestPackagesCsv[$i].Name -replace '[\W]','')','$($TestPackagesCsv[$i].Method -replace '[\W]','')','$($TestPackagesCsv[$i].Assignment -replace '[\W]','')');"
    }
    $ImportTablePackagesData = $ImportTablePackagesData + "COMMIT;"

    #Import the horrible mess I have generated
    .\sqlite3.exe $script:db $ImportTablePackagesData
}

function Get-TableContents {
    param( [Parameter(Mandatory=$true, ValueFromPipeline=$false)][string]$Table)

    switch ($Table) {
         "In" { $Header = 'Id','Device','Package','TaskRef','DateCreated' }
         "Packages" { $Header = 'Id','Name','Method','Assignment' }
         "WorkingTable" { $Header =  'Id','Device','TaskRef','DateCreated', 'Method', 'Assignment' }
        Default { throw "Table Ref invalid: Unknown table provided: $Table" }
    }

    $GetTable = "BEGIN TRANSACTION;
        SELECT * FROM '$Table';
        COMMIT;"

    #Export it as a csv then reimport it as a dirty way to make it an object
    $TempCsv = ".\TempCsv.csv"
    $GetTable > $TempCsv
    $Output = Import-Csv -Path $TempCsv -Header $Header -Delimiter "`|"

    Remove-Item -Path $TempCsv -Force

    return $Output
}

function Invoke-Runtime {        
    #Left join the tables to save processing in script as the data is right there. Could use a view but eh.
    $CreateWorkingTable = 'START TRANSACTION;
    DROP TABLE IF EXISTS WorkingTable;
    CREATE TABLE WorkingTable AS
        SELECT 
            L.Id, 
            L.Device, 
            L.TaskRef, 
            L.DateCreated, 
            P.Method, 
            P.Assignment
        FROM "In" L
        LEFT JOIN Packages P ON P.Name = L.Package;
        COMMIT;'
    
    .\sqlite3.exe $Script:db $CreateWorkingTable

    $ToProcess = Get-TableContents -Table WorkingTable

    #Set up the output Transaction
    $EndingTransaction = "BEGIN TRANSACTION;"

    foreach ( $ToProcessObject in $ToProcess ) {

        switch ( $ToProcessObject. ) {
            "AD" { Add-AdGroupMember -Identity $ToProcessObject.Assignment -Member $ToProcessObject.Device -Confirm:$false }
            "SCCM" { (Get-CMDevice -Name $ToProcessObject.Device). | Add-CMDevice }
            Default { Throw "Unknown delivery system, review Packages.csv" }

        }
    }
}


Start-Checks
for (;;){
    Start-Sleep -Seconds 10
    Invoke-Runtime
}