###########################
# useful string libraries #
###########################

$_sqlAgentJobManifestConfiguration = @{
    InfoMacro = @{
        Title = 'Schedule View';
        BodyTemplate = 'Check out the {0} for a summary of execution schedules for these jobs!'
        LinkText = 'Schedule Overview'
    };
    PagePropertiesMacro = @{
        Title = 'Job List'
        Cql = "label = &quot;sql-agent-job&quot; and space = currentSpace() and ancestor = currentContent()";
        PageSize = "100"
        FirstColumn = "Job"
        Headings = "Description,Enabled,Schedules,Steps,Owner,Created,Last Modified"
        SortBy = "Title"
    }
}



$_pageLabels = @{
    SqlAgentJob = 'sql-agent-job'
}

###################################
# sql agent job various utilities #
###################################

function Get-SqlAgentJobScheduleWithTranslation() {
  Begin {
    #start a list to hold augmented schedule objects
    $translatedSchedules = @()
  }

  Process {
    #iterate over schedules for each job, and build a new schedule object with additional properties
    foreach($SqlAgentJobSchedule in $_ | Get-SqlAgentJobSchedule) {
        
        #give an easier name to the schedule object
        $translated = $SqlAgentJobSchedule
        
        #define some convenient variables we'll be using from the cloned object
        $FrequencyType = $translated.FrequencyTypes
        $FrequencyInterval = $translated.FrequencyInterval
        $FrequencyRecurrenceFactor = $translated.FrequencyRecurrenceFactor
        $FrequencyRelativeInterval = $translated.FrequencyRelativeIntervals
        $ActiveStartDate = $translated.ActiveStartDate
        $FrequencySubDayType = $translated.FrequencySubDayTypes
        $FrequencySubDayInterval = $translated.FrequencySubDayInterval
        $ActiveStartTimeOfDay = $translated.ActiveStartTimeOfDay

        #add new properties to hold derived translations
        $translated | Add-Member -MemberType AliasProperty -Name JobName -Value Parent -Force
        $translated | Add-Member -MemberType AliasProperty -Name ScheduleEnabled -Value IsEnabled -Force
        $translated | Add-Member -MemberType AliasProperty -Name ScheduleName -Value Name -Force
        $translated | Add-Member -MemberType NoteProperty -Name JobEnabled -Value $_.IsEnabled -Force
        $translated | Add-Member -MemberType NoteProperty -Name StartTimeTranslation -Value (Get-Date -Hour $ActiveStartTimeOfDay.Hours -Minute $ActiveStartTimeOfDay.Minutes -Format t) -Force
        $translated | Add-Member -MemberType NoteProperty -Name StartDateTranslation -Value ("beginning " + $ActiveStartDate.ToString("d")) -Force
        $translated | Add-Member -MemberType NoteProperty -Name FrequencyTypeTranslation -Value $FrequencyType.ToString() -Force
        $translated | Add-Member -MemberType NoteProperty -Name FrequencyIntervalTranslation -Value $FrequencyInterval.ToString() -Force
        $translated | Add-Member -MemberType NoteProperty -Name FrequencySubDayTranslation -Value "Once" -Force
        $translated | Add-Member -MemberType NoteProperty -Name FrequencyRecurrenceFactorTranslation -Value $FrequencyType.ToString() -Force
        $translated | Add-Member -MemberType NoteProperty -Name FrequencyRelativeIntervalTranslation -Value $FrequencyRelativeInterval.ToString() -Force
        $translated | Add-Member -MemberType NoteProperty -Name FrequencyTranslation -Value "" -Force
        $translated | Add-Member -MemberType NoteProperty -Name TimingTranslation -Value "" -Force

        #translate frequency values and assign them to the new object
        switch ($FrequencyType) {
            "Daily" {
                #set properties
                $translated.FrequencyTranslation = "Every $FrequencyInterval day(s)"
            }
            "Weekly" {
                #decode the frequency interval to a list of days using bitwise logic (and magic knowledge)
                $days = @()
                if ($FrequencyInterval -band 1) { $days += "Sunday" }
                if ($FrequencyInterval -band 2) { $days += "Monday" }
                if ($FrequencyInterval -band 4) { $days += "Tuesday" }
                if ($FrequencyInterval -band 8) { $days += "Wednesday" }
                if ($FrequencyInterval -band 16) { $days += "Thursday" }
                if ($FrequencyInterval -band 32) { $days += "Friday" }
                if ($FrequencyInterval -band 64) { $days += "Sunday" }

                #set properties
                if($FrequencyRecurrenceFactor -gt 1) { $translated.FrequencyRecurrenceFactorTranslation = "Every $FrequencyRecurrenceFactor weeks" }
                $translated.FrequencyIntervalTranslation = ($days -join ", ")
                $translated.FrequencyTranslation =  $translated.FrequencyRecurrenceFactorTranslation + ", on " + $translated.FrequencyIntervalTranslation
            }
            "Monthly" {
                #set properties
                if($FrequencyRecurrenceFactor -gt 1) { $translated.FrequencyRecurrenceFactorTranslation = "Every $FrequencyRecurrenceFactor months" }
                $translated.FrequencyIntervalTranslation = "day $FrequencyInterval of the month"
                $translated.FrequencyTranslation = $translated.FrequencyRecurrenceFactorTranslation + ", on " + $translated.FrequencyIntervalTranslation
            }
            "MonthlyRelative" {
                #use magic knowledge to decode the frequency interval
                $translated.FrequencyIntervalTranslation = switch ($FrequencyInterval) {
                    1 { "Sunday" }
                    2 { "Monday" }
                    3 { "Tuesday" }
                    4 { "Wednesday" }
                    5 { "Thursday" }
                    6 { "Friday" }
                    7 { "Saturday" }
                    8 { "day" }
                    9 { "weekday" }
                    10 { "weekend day" }
                    default { "Unknown Interval" }
                }

                #set properties
                if($FrequencyRecurrenceFactor -gt 1) {
                    $translated.FrequencyRecurrenceFactorTranslation = "Every $FrequencyRecurrenceFactor months"
                } else {
                    $translated.FrequencyRecurrenceFactorTranslation = "Monthly"
                }
                $translated.FrequencyRelativeIntervalTranslation = $FrequencyRelativeInterval.ToString().ToLower() + " " + $translated.FrequencyIntervalTranslation + " of the month"
                $translated.FrequencyTranslation = $translated.FrequencyRecurrenceFactorTranslation + ", on the " + $translated.FrequencyRelativeIntervalTranslation
            }
            default { $translated.FrequencyTranslation = "Unknown Interval" }
        }

        #translate timing values and assign them to the new object
        if ($FrequencySubDayType -ne "Once") {
            $translated.FrequencySubDayTranslation += " every $FrequencySubDayInterval " + $FrequencySubDayType.ToString().ToLower() + "(s)"
        }
        $translated.TimingTranslation = $translated.FrequencySubDayTranslation + " starting at " + $translated.StartTimeTranslation        
        
        #add the object with the new properties to the return list
        $translatedSchedules += $translated
    }
  }

  End {
    #return
    $translatedSchedules
  }
  
}

function Get-SqlAgentJobStepPackagePath($SqlAgentJobStep) {
    $package = ""
    foreach ($str in $SqlAgentJobStep.Command.Split("/")) {
        if ($str.StartsWith("ISSERVER")) {
            $trimStr = $str.Substring(9)
            $trimStr = $trimStr.Replace('\"','')
            $trimStr = $trimStr.Replace('"','')
            $trimStr = $trimStr.Substring(8)
            $package = $trimStr
            break
        }
    }
    $package
}

#########################################
# sql agent job manifest page utilities #
#########################################

function Format-SqlAgentJobManifestConfluencePage($SchedulePageTitle="", $UserSection = (Format-ConfluenceDefaultUserSection)) {
    $pageContents = @()

    # create info macro
    $link = Format-ConfluencePageLink -TargetPageTitle $SchedulePageTitle -LinkText $_sqlAgentJobManifestConfiguration.InfoMacro.LinkText
    $macroBody = (New-ConfluenceHtmlTag -Tag "p" -Contents ($_sqlAgentJobManifestConfiguration.InfoMacro.BodyTemplate -f $link)).ToString()
    $pageContents += Format-ConfluenceMessageBoxMacro -Type (Get-ConfluenceMessageBoxTypes).Info -MessageBody $macroBody -Title $_sqlAgentJobManifestConfiguration.InfoMacro.Title
    
    # add the page properties report
    $pageContents += (New-ConfluenceHtmlTag -Tag "h1" -Contents $_sqlAgentJobManifestConfiguration.PagePropertiesMacro.Title).ToString()
    $pageContents += Format-ConfluencePagePropertiesReportMacro -Cql $_sqlAgentJobManifestConfiguration.PagePropertiesMacro.Cql -PageSize $_sqlAgentJobManifestConfiguration.PagePropertiesMacro.PageSize -FirstColumn $_sqlAgentJobManifestConfiguration.PagePropertiesMacro.FirstColumn -Headings $_sqlAgentJobManifestConfiguration.PagePropertiesMacro.Headings -SortBy $_sqlAgentJobManifestConfiguration.PagePropertiesMacro.SortBy

    $map = $ContentMap
    if ($map -eq $null) {$map=@($null,@{Generated=$false;Content=Format-ConfluenceDefaultUserSection})}
    $map[0] = @{Generated=$true;Content=$pageContents}

    # return
    Format-ConfluencePageBase -ContentMap $map
}

function Add-SqlAgentJobManifestConfluencePage($ConfluenceConnection,$SpaceKey,$PageTitle,$SchedulePageTitle,$AncestorID=-1) {
    $pageContents = Format-SqlAgentJobManifestConfluencePage -SchedulePageTitle $SchedulePageTitle
    Add-ConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $PageTitle -Contents $pageContents -AncestorID $AncestorID
}

function Update-SqlAgentJobManifestConfluencePage($ConfluenceConnection,$Page,$PageTitle,$SchedulePageTitle) {
    # use an updated title, or keep the old title if a new one is not supplied
    $updateTitle = (&{if($PageTitle -eq "") {$Page.title} else {$PageTitle}})

    # get the content map
    $contentMap = (Get-ConfluenceContentMap -TemplateContent $Page.body.storage.value)

    # render the content
    $pageContents = Format-SqlAgentJobManifestConfluencePage -SchedulePageTitle $SchedulePageTitle -ContentMap $contentMap

    # post the update
    Update-ConfluencePage -ConfluenceConnection $ConfluenceConnection -PageID $Page.id -CurrentVersion $Page.version.number -Title $updateTitle -Contents $pageContents
}

function Publish-SqlAgentJobManifestConfluencePage($ConfluenceConnection,$SpaceKey,$PageTitle,$SchedulePageTitle,$AncestorID=-1) {
    #look for an existing page
    $page = Get-ConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $PageTitle -Expand @("body.storage","version")
    if ($page) {
        # update the page if it exists
        Update-SqlAgentJobManifestConfluencePage -ConfluenceConnection $ConfluenceConnection -Page $page -PageTitle $PageTitle -SchedulePageTitle $SchedulePageTitle
    } else {
        #create one if it doesn't
        Add-SqlAgentJobManifestConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -PageTitle $PageTitle -SchedulePageTitle $SchedulePageTitle -AncestorID $AncestorID
    }
}

#############################################
# sql agent schedule summary page utilities #
#############################################

function Format-SqlAgentScheduleSummaryConfluencePage($Schedules, $ContentMap=$null) {
    $rows = @()
    
    # create the header row
    $headers = @(
        "Job Name",
        "Job Enabled",
        "Schedule Name",
        "Schedule Enabled",
        "Execution Frequency",
        "Execution Time"
    )
    $headerCells = $headers | ForEach-Object { New-ConfluenceHtmlTableCell $_ }  
    $rows += New-ConfluenceHtmlTableRow -Cells $headerCells -Header

    # build out the schedule rows
    foreach ($schedule in $Schedules) {
        $jobNameLink = (Format-ConfluencePageLink -TargetPageTitle $schedule.Parent -LinkText $schedule.Parent)

        $cells = @()
        $cells += New-ConfluenceHtmlTableCell -Contents $jobNameLink
        $cells += New-ConfluenceHtmlTableCell -Contents (Format-ConfluenceIcon -Icon $schedule.JobEnabled) -Center $true
        $cells += New-ConfluenceHtmlTableCell -Contents $schedule.Name
        $cells += New-ConfluenceHtmlTableCell -Contents (Format-ConfluenceIcon -Icon $schedule.IsEnabled) -Center $true
        $cells += New-ConfluenceHtmlTableCell -Contents $schedule.FrequencyTranslation
        $cells += New-ConfluenceHtmlTableCell -Contents $schedule.StartTimeTranslation
        $rows += New-ConfluenceHtmlTableRow -Cells $cells
    }
    
    # pull it all together
    $title = (New-ConfluenceHtmlTag -Tag "h1" -Contents "SQL Agent Job Schedule Summary").ToString()
    $table = (New-ConfluenceHtmlTable -Rows $rows).ToString()

    $pageContent = $title + $table

    $map = $ContentMap
    if ($map -eq $null) {$map=@($null,@{Generated=$false;Content=Format-ConfluenceDefaultUserSection})}
    $map[0] = @{Generated=$true;Content=$pageContent}

    # return
    Format-ConfluencePageBase -ContentMap $map
}

function Add-SqlAgentScheduleSummaryConfluencePage($ConfluenceConnection,$SpaceKey,$AncestorID=-1,$Title="",$Schedules) {
    $pageContents = Format-SqlAgentScheduleSummaryConfluencePage -Schedules $Schedules
    Add-ConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $Title -Contents $pageContents -AncestorID $AncestorID
}

function Update-SqlAgentScheduleSummaryConfluencePage($ConfluenceConnection,$Page,$Title="",$Schedules) {
    
    # use an updated title, or keep the old title if a new one is not supplied
    $updateTitle = (&{if($Title -eq "") {$Page.title} else {$Title}})

    # get the content map
    $contentMap = (Get-ConfluenceContentMap -TemplateContent $Page.body.storage.value)

    # render the content
    $pageContents = Format-SqlAgentScheduleSummaryConfluencePage -Schedules $Schedules -ContentMap $contentMap

    # post the update
    Update-ConfluencePage -ConfluenceConnection $ConfluenceConnection -PageID $Page.id -CurrentVersion $Page.version.number -Title $updateTitle -Contents $pageContents
}

function Publish-SqlAgentScheduleSummaryConfluencePage($ConfluenceConnection,$SpaceKey,$Title,$Schedules,$AncestorID=-1) {
    #look for an existing page
    $page = Get-ConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $Title -Expand @("body.storage","version")
    if ($page) {
        # update the page if it exists
        Update-SqlAgentScheduleSummaryConfluencePage -ConfluenceConnection $ConfluenceConnection -Page $page -Schedules $Schedules
    } else {
        #create one if it doesn't
        Add-SqlAgentScheduleSummaryConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $Title -Schedules $Schedules -AncestorID $AncestorID
    }
}

################################
# sql agent job page utilities #
################################

function Format-SqlAgentJobConfluencePageProperties($SqlAgentJob) {
    #define the properties as key-value pairs in an array
    $properties = @(
        @{"SQL Agent Job Name" = $SqlAgentJob.Name}
        @{Description = (&{if($SqlAgentJob.Description -ne ""){[System.Net.WebUtility]::HtmlEncode($SqlAgentJob.Description)}else{"N/A"}})},
        @{Enabled = Format-ConfluenceIcon -Icon $SqlAgentJob.IsEnabled},
        @{Schedules = ($SqlAgentJob|Get-SqlAgentJobSchedule|Measure-Object).Count},
        @{Steps = ($SqlAgentJob|Get-SqlAgentJobStep|Measure-Object).Count},
        @{Owner = $SqlAgentJob.OwnerLoginName},
        @{Created = Format-ConfluenceDate($SqlAgentJob.DateCreated)},
        @{"Last Modified" = Format-ConfluenceDate($SqlAgentJob.DateLastModified)}
    )
    (New-ConfluenceHtmlTag -Tag "h1" -Contents "Properties").ToString() + (Format-ConfluencePagePropertiesMacro -Properties $properties)
}

function Format-SqlAgentJobConfluencePageSchedules($SqlAgentJob) {
    $rows = @()

    # create the header row
    $headers = @(
        "Schedule Name",
        "Enabled",
        "Execution Frequency",
        "Execution Time",
        "Activation Date",
        "Date Created"
    )    
    $headerCells = $headers | ForEach-Object { New-ConfluenceHtmlTableCell $_ }  
    $rows += New-ConfluenceHtmlTableRow -Cells $headerCells -Header

    # create the schedule rows
    $schedules = $SqlAgentJob | Get-SqlAgentJobScheduleWithTranslation
    foreach ($schedule in $schedules) {
        $cells = @(
            (New-ConfluenceHtmlTableCell -Contents $schedule.Name),
            (New-ConfluenceHtmlTableCell -Contents (Format-ConfluenceIcon -Icon $schedule.IsEnabled)),
            (New-ConfluenceHtmlTableCell -Contents $schedule.FrequencyTranslation),
            (New-ConfluenceHtmlTableCell -Contents $schedule.StartTimeTranslation),
            (New-ConfluenceHtmlTableCell -Contents Format-ConfluenceDate($schedule.ActiveStartDate)),
            (New-ConfluenceHtmlTableCell -Contents Format-ConfluenceDate($schedule.DateCreated))
        )
        $rows += New-ConfluenceHtmlTableRow -Cells $cells
    }

    # return the title and the table
    (New-ConfluenceHtmlTag -Tag "h1" -Contents "Schedule(s)").ToString() + (New-ConfluenceHtmlTable -Rows $rows).ToString()
}

function Format-SqlAgentJobConfluencePageSteps($SqlAgentJob) {
    $rows = @()

    # create the header row
    $headers = @(
        "#",
        "Step Name",
        "Step Type",
        "Package",
        "Package Path",
        "On Fail",
        "On Success"
    )    
    $headerCells = $headers | ForEach-Object { New-ConfluenceHtmlTableCell $_ }  
    $rows += New-ConfluenceHtmlTableRow -Cells $headerCells -Header

    # create the step rows
    $steps = $SqlAgentJob | Get-SqlAgentJobStep
    foreach ($step in $steps) {
        # prepare some package details
        $packageFullPath = Get-SqlAgentJobStepPackagePath($step)
        $packagePathArr = $packageFullPath.Split('\')
        $failAction = $($step.OnFailAction -csplit "(?<=.)(?=[A-Z])")
        $successAction = $($step.OnSuccessAction -csplit "(?<=.)(?=[A-Z])")
        $numberContents = "" + $step.ID + (&{If($SqlAgentJob.StartStepID -eq $step.ID) {" " + (Format-ConfluenceIcon -Icon $PC_ConfluenceEmoticons.StarYellow)} Else {""}})
        
        # create the cells
        $cells = @(
            (New-ConfluenceHtmlTableCell -Contents $numberContents),
            (New-ConfluenceHtmlTableCell -Contents $step.Name),
            (New-ConfluenceHtmlTableCell -Contents $step.SubSystem),
            (New-ConfluenceHtmlTableCell -Contents $packagePathArr[2]),
            (New-ConfluenceHtmlTableCell -Contents ($packagePathArr[0] + '\' + $packagePathArr[1])),
            (New-ConfluenceHtmlTableCell -Contents "$failAction"),
            (New-ConfluenceHtmlTableCell -Contents "$successAction")
        )

        # render the row and add it to the list
        $rows += New-ConfluenceHtmlTableRow -Cells $cells
    }

    # build the return string
    $header = (New-ConfluenceHtmlTag -Tag "h1" -Contents "Step(s)").ToString()
    $note = (New-ConfluenceHtmlTag -Tag "p" -Contents ((Format-ConfluenceIcon -Icon $PC_ConfluenceEmoticons.StarYellow) + "&nbsp;= First Step")).ToString()
    $table = (New-ConfluenceHtmlTable -Rows $rows).ToString()

    # return
    "$header$note$table"
}

function Format-SqlAgentJobConfluencePage($SqlAgentJob, $ContentMap=$null) {
    $pageContent = @()
    $pageContent += Format-SqlAgentJobConfluencePageProperties($SqlAgentJob)
    $pageContent += Format-SqlAgentJobConfluencePageSchedules($SqlAgentJob)
    $pageContent += Format-SqlAgentJobConfluencePageSteps($SqlAgentJob)
    $map = $ContentMap
    if ($map -eq $null) {$map=@($null,@{Generated=$false;Content=Format-ConfluenceDefaultUserSection})}
    $map[0] = @{Generated=$true;Content=$pageContent}
    Format-ConfluencePageBase -ContentMap $map
}

function Add-SqlAgentJobConfluencePage($ConfluenceConnection,$SqlAgentJob, $SpaceKey, $AncestorID = -1) {
    $pageContents = Format-SqlAgentJobConfluencePage -SqlAgentJob $SqlAgentJob
    $title = $SqlAgentJob.Name
    $newPage = Add-ConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $title -Contents $pageContents -AncestorID $AncestorID
    $newPage
    Add-ConfluencePageLabel -ConfluenceConnection $ConfluenceConnection -PageID $newPage.id -LabelName $_pageLabels.SqlAgentJob
}

function Update-SqlAgentJobConfluencePage($ConfluenceConnection,$SqlAgentJob,$Page,$Title="") {
    # use an updated title, or keep the old title if a new one is not supplied
    $updateTitle = (&{if($Title -eq "") {$Page.title} else {$Title}})

    # get the content map
    $contentMap = (Get-ConfluenceContentMap -TemplateContent $Page.body.storage.value)

    # render the content
    $pageContents = Format-SqlAgentJobConfluencePage -SqlAgentJob $SqlAgentJob -ContentMap $contentMap

    # post the update
    Update-ConfluencePage -ConfluenceConnection $ConfluenceConnection -PageID $Page.id -CurrentVersion $Page.version.number -Title $updateTitle -Contents $pageContents

    # determine if we need to add a label as well
    $label = $Page.metadata.labels.results | Where-Object {$_.name -eq $_pageLabels.SqlAgentJob}
    if (-not $label) {
        Add-ConfluencePageLabel -ConfluenceConnection $ConfluenceConnection -PageID $Page.id -LabelName $_pageLabels.SqlAgentJob
    }
}

function Publish-SqlAgentJobConfluencePage($ConfluenceConnection,$SqlAgentJob,$SpaceKey,$Title="",$AncestorID = -1) {
    # search using the supplied title (if one is given) or the name of the job as the title
    $searchTitle = (&{if($Title -eq "") {$SqlAgentJob.Name} else {$Title}})
    
    #look for an existing page
    $page = Get-ConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $searchTitle -Expand @("body.storage","version","metadata.labels")
    if ($page) {
        # update the page if it exists
        Update-SqlAgentJobConfluencePage -ConfluenceConnection $ConfluenceConnection -Page $page -SqlAgentJob $SqlAgentJob -Title $searchTitle
    } else {
        #create one if it doesn't
        Add-SqlAgentJobConfluencePage -ConfluenceConnection $ConfluenceConnection -SpaceKey $SpaceKey -Title $searchTitle -AncestorID $AncestorID -SqlAgentJob $SqlAgentJob
    }
}

Export-ModuleMember -Function * -Variable *