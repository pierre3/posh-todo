Add-Type -TypeDefinition @'
using System;
using System.Management.Automation;
using System.Collections;

public enum TodoStatus
{
    Todo, Milestone, Doing, Done
}

public class TodoItem
{
    public int index { get; set; }
    public string text { get; set; }
    public DateTime date { get; set; }
    public bool flag { get; set; }
    public TodoStatus status { get; set; }
    public static explicit operator TodoItem(PSObject source){
        dynamic d = source;
        return new TodoItem(){
            index = (int)d.index,
            text = (string)d.text,
            date = (DateTime)d.date,
            flag = (bool)d.flag,
            status = (TodoStatus)d.status
        };
    }
}
'@ -ReferencedAssemblies "Microsoft.CSharp"

$todo = [PSObject]@{
    filePath = "";
    items = [TodoItem[]]@();
    filter = [scriptblock]{$true};
    sortkey = 'date';
}

function Get-DatePicker
{
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    Param([string]$windowTitle=$null)

    Add-type -AssemblyName "System.windows.forms"
    $winForm = New-object Windows.Forms.Form
    if([string]::IsNullOrEmpty($windowTitle)){
        $winForm.Text = "DatePicker Control"
    }else{
        $winForm.Text = $windowTitle
    }
    $winForm.Size = New-Object Drawing.Size(200,55)
    $winForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $winform.Add_Shown({ $winForm.TopMost = $true; $winForm.Activate(); })
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Add_KeyPress({ 
        if($_.KeyChar -eq [System.Char][System.Windows.Forms.Keys]::Enter){ 
            $winForm.Close()
        }
    })
    $winForm.Controls.Add($datePicker)
    $winform.ShowDialog() | Out-null
    $datePicker.Value.Date
}

function Show-TodoItems
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            Position=0)]
        [TodoItem[]]
        $inputTodoItems
    )
    begin{}
    process
    {
        foreach($item in $inputTodoItems)
        {
            if($item.date -eq $null)
            {
                $item.date = [datetime]::MaxValue
            }
            $s_date = $item.date.ToLocalTime().ToString("yyyy/MM/dd")
            $s_index = $item.index.ToString("00")
            if($item.flag){
                $s_flag  = " !" 
            }else{
                $s_flag = " ."
            }
            $_status_ = ([TodoStatus]$item.status).ToString()
            switch($_status_)
            {
                Done {
                    $s_status = "✔"
                    $bgColor = [ConsoleColor]::Gray
                    $fgColor = [ConsoleColor]::Black
                }
                Milestone {
                    $s_status = "◆"
                    $bgColor = [ConsoleColor]::Yellow
                    $fgColor = [ConsoleColor]::Black
                }
                Doing {
                    $s_status = "▶"
                    if($s_flag -eq " !"){
                        $bgColor = [ConsoleColor]::DarkMagenta
                        $fgColor = [ConsoleColor]::White
                    }else{
                        $bgColor = $null
                        $fgColor = $null
                    }
                }
                default {
                    $s_status = "▢"
                    if($s_flag -eq " !"){
                        $bgColor = [ConsoleColor]::DarkMagenta
                        $fgColor = [ConsoleColor]::White
                    }else{
                        $bgColor = $null
                        $fgColor = $null
                    }
                }
            }
            $output = "$s_index. $s_status$s_flag[$s_date] $($item.text)"
            if( ($bgColor -ne $null) -and ($fgColor -ne $null) ) {
                Write-Host $output -ForegroundColor $fgColor -BackgroundColor $bgColor
            }else {
                Write-Host $output
            }
        }
    }
}

function Read-TodoItems
{
    Param(
        [string]
        $path = $todo.filePath
    )
    
    $obj = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    
    if($obj -eq $null){
        $todo.items = [TodoItem[]]@()
    } else {
        $_todoitems_ = $obj | % -Begin { $i=0} {
            $item = [TodoItem]$_
            $item.index = $i++
            $item
        }
        $todo.items = @($_todoitems_)
    }
    $todo.items
}

function Add-Todo
{
    [CmdletBinding()]
    Param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [string[]]
        $inputStrings,
        [switch]
        $setDate
    )

    Begin {}
    Process {
        foreach($line in $inputStrings)
        {
            $text = $line
            $flag = $false
            $status = [TodoStatus]::Todo
            $date = [DateTime]::MaxValue

            if($line -match "^\[.+\]") {
                $flag = $Matches[0].Contains("!")
                if($Matches[0].Contains("*")){
                    $status = [TodoStatus]::Milestone
                }
                $text = $line.Replace($Matches[0], "")
            }
             
            if($setDate){
                $date = (Get-DatePicker $text)
            }

            $todo.items += [TodoItem]@{
                index = 0;
                text = $text;
                date = $date
                flag = $flag;
                status = $status;
            }
        }
    }
    end {
        $todo.items | % -Begin { $i = 0 } {$_.index = $i++ }
        Write-TodoItems
        Show-TodoList
    }
}

function Write-TodoItems
{
    Param(
        [string]
        $path = $todo.filePath
    )

    Copy-Item -Path $path -Destination "$path.backup"
    ConvertTo-Json $todo.items | Out-File $path -Encoding utf8
}

function Show-TodoList
{
    Write-Host "##### ToDo List #####"
    if(Test-Path $todo.filePath)
    {
        Read-TodoItems |
        Where-Object -FilterScript $todo.filter |
        Sort-Object -Property $todo.sortKey |
        Show-TodoItems
    }
    Write-Host ""
}

function Set-TodoStatus
{
    [CmdletBinding()]
    Param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position=0
        )]
        [int[]]
        $index,
        [TodoStatus]
        $status = [TodoStatus]::Done
    )
    begin{}
    process{
        foreach($i in $index){
            if(($i -lt 0) -or ($i -ge $todo.items.Length)){
                continue;
            }
            $todo.items[$i].status = $status;
        }
    }
    end{
        Write-TodoItems
        Show-TodoList
    }
}

function Remove-Todo
{
    [CmdletBinding()]
    Param(
        [Parameter(Position=0)]
        [int[]]
        $index,
        [TodoStatus]
        $status,
        [scriptblock]
        $filter = {$true}
    )

    begin{$result = @()}
    process{
        $todo.items = $todo.items | ?{
            $indexUnMatch = $false
            if($index -ne $null){
                $indexUnMatch = -not ($index.Contains($_.index))
            }
            $statusUnMatch = $false
            if($status -ne $null){
                $statusUnMatch = $_.status -ne $status
            }
            $filterUnMatch = -not($filter.Invoke($_))
            $indexUnMatch -or $statusUnMatch -or $filterUnMatch
        }
    }
    end{
        Write-TodoItems
        Show-TodoList
    }
}

function Remove-PastTodoItem
{
    Remove-Todo -status Done -filter {
        Param([TodoItem]$td)
        $td.date.Date.ToLocalTime() -le (Get-Date).Date
    }
}

function Start-PoshTodo
{
    Param(
        [string]$path,
        [switch]$Force)

    if(-not(Test-Path $path)){
        if($Force){
            New-Item $path -Force -ItemType file
        }else{
            New-Item $path -ItemType file
        }
    }
    $todo.filePath = $path
    Show-StartingMessage
    Show-TodoList
}

function Show-StartingMessage
{
    $today = (Get-Date).ToString("yyyy/MM/dd")
    Write-Host "こんにちは $env:USERNAME さん！ 今日は $today です。"
    Write-Host ('{0}も{1}{2}{3}{4}ぞい!' -f ('今日', '１', '日', 'がん', 'ばる' | % { ($_,'ぞい')[(random 2)] }))
}

Set-Alias atodo Add-Todo
Set-Alias rmtodo Remove-Todo
Set-Alias todostat Set-TodoStatus
Set-Alias todolst Show-todoList

Export-ModuleMember `
    -Function * `
    -Alias * `
    -Variable "todo"
