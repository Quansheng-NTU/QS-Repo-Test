# To check if any data file size is approaching 32 Gbytes limit.
# To execute from OMS server.
# Select-String -Path test_tnsping.log -Pattern "msec"
# History
# 2022-May-10 QS Initialized
# 2022-Sep-27 QS test Github
# 2022-Sep-27 QS test checkpoint 1
# 2022-Sep-27 QS test checkpoint 2
# 2022-Sep-27 QS test checkpoint 3

#$DBNAME="ACAD"
$USERNAME="dbapadm"
#$SERVERNAME="ALPHA"
#$TNSNAME="ALPHA_1521"

# Read oradb.ini
$DBHealth_BASE="C:\REMOTE_DST_DBHealth\Oracle"
$SCRIPT_DIR="$DBHealth_BASE\Scripts"
$ORADB_FILE="$SCRIPT_DIR\oradb.ini"
$ORADB_HEARDER='DBName','InstanceName','HostName','TNSName'
$ORADB = Import-Csv -Path $ORADB_FILE -Delimiter ":" -Header $ORADB_HEARDER

$PWD_FILE="$SCRIPT_DIR\oradb_pwd.txt"

$LOG_DIR="$DBHealth_BASE\logs"
$TEST_LOG="$LOG_DIR\chk_DBCapacity_test.log"
$STATUS_REPORT="$LOG_DIR\chk_DBCapacity_rpt.txt"
$CSV_OUTPUT_DIR="$DBHealth_BASE\Output\DBCapacity"

$Env:ORACLE_HOME="D:\app\oracle\product\19.0.0\dbhome_1"
$Env:PATH +=";$Env:ORACLE_HOME\bin"

$STATUS_WARN=0
write-output "" | out-file $STATUS_REPORT -encoding "UTF8"

foreach ($iORADB in $ORADB)
{
  Write-Host ""
  write-host "DBName is: " $iORADB.DBName
  write-host "InstanceName is: " $iORADB.InstanceName
  write-host "HostName is: " $iORADB.HostName
  write-host "TNSName is: " $iORADB.TNSName

  $iDBName=$iORADB.DBName
  $iInstanceName=$iORADB.InstanceName
  $iHostName=$iORADB.HostName
  $iTNSName=$iORADB.TNSName

  $CURR_DATE=(get-date -Format "ddMMMyyyy")
  $CSV_OUTPUT=$CSV_OUTPUT_DIR + "\DBCapacity_" + $iHostName + "_" + $CURR_DATE + ".csv"

  $USERPWD=(((Get-Content $PWD_FILE | Select-String -Pattern "#" -NotMatch | Select-String -Pattern $iORADB.DBName | select-string -pattern $USERNAME  | Out-string) -replace "\n","" ).split(":",3) | select -index 2).trim()
  
  write-host "USER PWD IS " $USERPWD " " $USERNAME

  $(
    sqlplus -s $USERNAME/$USERPWD@$iTNSName @$SCRIPT_DIR\chk_DBCapacity.sql $CSV_OUTPUT
  ) *>&1 > $TEST_LOG

  $LINE_CNT=(get-content $TEST_LOG |select-string "ORA-" ).length 

  write-host "ORA- error message count: $LINE_CNT"

  if ( $LINE_CNT -gt 0 )
  { write-output "Found error while generating ORA DBCapacity report on $iTNSName." | out-file $STATUS_REPORT -append -encoding "UTF8"
    Get-Content $TEST_LOG  | out-file $STATUS_REPORT -append -encoding "UTF8" 
    $STATUS_WARN=$STATUS_WARN+1
  }
  else
  { write-output "$iTNSName ORA DBCapacity report is generated." | out-file $STATUS_REPORT -append -encoding "UTF8" }

  # Get server volume metrics.
  #  write-output "Server volume capacity." | out-file $CSV_OUTPUT -append -encoding "UTF8"
  #  #write-output "Server Drive,Capacity GB, UsedSpace GB." | out-file $CSV_OUTPUT -append -encoding "UTF8"
  #  gwmi Win32_LogicalDisk -ComputerName $iHostName -Filter "DriveType=3" `
  #   | select Name,FreeSpace,FreePCT,Size,UsedSpace `
  #   | % {$_.FreePCT=(($_.FreeSpace)/($_.Size))*100;$_.FreeSpace=($_.FreeSpace/1GB);$_.Size=($_.Size/1GB);$_.UsedSpace=($_.Size-$_.FreeSpace);$_} `
  #   | Format-Table @{n='Server'     ;e={$iHostName}}`
  #                , Name `
  #                , @{n='Capacity GB';e={'{0:N2}' -f $_.Size};     a='right'}`
  #                , @{n='Used GB'    ;e={'{0:N2}' -f $_.UsedSpace};a='right'}`
  #                , @{n='FreePCT'    ;e={'{0:N2}' -f $_.FreePCT};a='right'}`
  #              -autosize   | out-file $CSV_OUTPUT -append -encoding "UTF8"

  # Get server volume metrics with space delimiter 
  gwmi Win32_LogicalDisk -ComputerName $iHostName -Filter "DriveType=3" `
   | select Name,FreeSpace,FreePCT,Size,UsedSpace `
   | % {$_.FreePCT=(($_.FreeSpace)/($_.Size))*100;$_.FreeSpace=($_.FreeSpace/1GB);$_.Size=($_.Size/1GB);$_.UsedSpace=($_.Size-$_.FreeSpace);$_} `
   | Format-Table @{n='Server'     ;e={$iHostName}}`
                , Name `
                , @{n='Capacity_GB';e={'{0:N2}' -f $_.Size};     a='right'}`
                , @{n='Used_GB'    ;e={'{0:N2}' -f $_.UsedSpace};a='right'}`
                , @{n='FreePCT'    ;e={'{0:N2}' -f $_.FreePCT};a='right'}`
              -autosize | out-file $LOG_DIR/temp1.log  

  # Remove empty lines.
  (Get-Content $LOG_DIR/temp1.log) | ? {$_.trim() -ne "" } | Set-Content $LOG_DIR/temp1.log

  # Convert space delimited file into CSV file.
  $input = Get-Content $LOG_DIR/temp1.log
  $data = $input[0..($input.Length - 1)]

  $maxLength = 0

  $objects = ForEach($record in $data) {
    $split = $record -split "\s{1,}"
    If($split.Length -gt $maxLength){
        $maxLength = $split.Length
    }
    $props = @{}
    For($i=0; $i -lt $split.Length; $i++) {
        $props.Add([String]($i+1),$split[$i])
        echo " $props"
    }
    New-Object -TypeName PSObject -Property $props
}

$headers = [String[]](1..$maxLength)

$objects | 
Select-Object $headers | 
Export-Csv -NoTypeInformation -Path $LOG_DIR/temp2.log

# Filter out unneccesary lines.
Get-Content $LOG_DIR/temp2.log | Select-String -pattern ",,,," -NotMatch | Out-File $LOG_DIR/temp3.log

get-content $LOG_DIR/temp3.log |select -skip 2 | Set-Content $LOG_DIR/temp4.log

# Append to CSV OUTPUT file.
echo "" | out-file $CSV_OUTPUT -append -encoding "UTF8"
get-content $LOG_DIR/temp4.log | out-file $CSV_OUTPUT -append -encoding "UTF8"

}

if ( $STATUS_WARN -gt 0)
{ $EMAIL_SUB="Monitoring:WARNING: Found error in ORA DBCapacity monitoring" }
else
{ $EMAIL_SUB="Monitoring:INFO: ORA DBCapacity report is generated" }

$EMAIL_LIST='CITS_DST@ntu.edu.sg'
$EMAIL_LIST="quansheng.zong@ntu.edu.sg"
$HOST_NAME=hostname
$EMAIL_BODY=cat $STATUS_REPORT|out-string
Send-MailMessage -SMTPServer confermail.ntu.edu.sg -To $EMAIL_LIST -From $HOST_NAME@ntu.edu.sg -Subject $EMAIL_SUB -Body $EMAIL_BODY
