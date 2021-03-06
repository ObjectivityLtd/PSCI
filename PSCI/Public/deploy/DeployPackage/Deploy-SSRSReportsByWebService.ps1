<#
The MIT License (MIT)

Copyright (c) 2015 Objectivity Bespoke Software Specialists

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

function Deploy-SSRSReportsByWebService {
    <#
    .SYNOPSIS
        Deploys a SSRS project using web service.

    .DESCRIPTION
        Deploys a SSRS project using rptproj file using given project configuration (Configuration parameter set) or using given project settings (Target parameter set).
        Compatible with SSRS versions 2008R2, 2012 and 2014.

    .PARAMETER PackageName
        Name of the SSRS package.

    .PARAMETER ProjectName
        Name of .rptproj project.

    .PARAMETER ProjectConfigurationName
        [PARAMETER SET = Configuration] Name of the project configuration to be used while deploying.

    .PARAMETER TargetServerURL
        [PARAMETER SET = Target] SSRS server url.

    .PARAMETER TargetFolder
        [PARAMETER SET = Target] SSRS target report folder name.

    .PARAMETER TargetDataSourceFolder
        [PARAMETER SET = Target] SSRS target data source folder name.

    .PARAMETER TargetDataSetFolder
        [PARAMETER SET = Target] SSRS target data set folder name.

    .PARAMETER DataSources
        [PARAMETER SET = Target] A hashtable containing data sources information to override, e.g. @{ 'mydatasource.rds' = New-SSRSDataSourceDefinition -ConnectString $Tokens.SSRS.MyConnectionString }
    
    .PARAMETER ReportItemsSecurity
        [PARAMETER SET = Target] A hashtable containing report items security permisions. @{ 'Folder' = @{ 'IIS APPPOOL\DefaultAppPool' = @( 'Browser', 'Publisher' ) } }

    .PARAMETER OverwriteDataSources
        [PARAMETER SET = Target] Set to $true in order to ovewrite data sources; $false otherwise. Defaults to $true.

    .PARAMETER OverwriteDatasets
        [PARAMETER SET = Target] Set to $true in order to ovewrite data sets; $false otherwise. Defaults to $true.

    .PARAMETER Credential
        Credentials used to connect to web service

    .PARAMETER PackagePath
    Path to the package containing SSRS files. If not provided, $PackagePath = $PackagesPath\$PackageName, where $PackagesPath is taken from global variable.

    .EXAMPLE
        Deploy-SSRSReportsByWebService -Path 'MyReports.rptproj' -Configuration 'Debug'
        Deploy-SSRSReportsByWebService -TargetServerUrl "http://localhost/reportserver" -TargetFolder "MyReports" -DataSourceFolder "Data Source" -DataSetFolder "Datasets"

    .LINK
        https://gist.github.com/Jonesie/9005796
    #>
    [CmdletBinding(DefaultParametersetName="Target")]
    [OutputType([void])]
    param (
        [Parameter(ParameterSetName='Target',Mandatory=$true)]
        [Parameter(ParameterSetName='Configuration',Mandatory=$true)]
        [string]
        $PackageName,

        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [Parameter(ParameterSetName='Configuration',Mandatory=$false)]
        [string] 
        $ProjectName,

        [Parameter(ParameterSetName='Configuration',Mandatory=$true)] 
        [string]
        $ProjectConfigurationName,
    
        [Parameter(ParameterSetName='Target',Mandatory=$true)]
        [ValidatePattern('^https?://')]
        [string]
        $TargetServerURL,
    
        [Parameter(ParameterSetName='Target',Mandatory=$true)]
        [string]
        $TargetFolder,

        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [string]
        $TargetDataSourceFolder,
    
        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [string]
        $TargetDataSetFolder,

        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [hashtable] 
        $DataSources,
        
        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [hashtable] 
        $ReportItemsSecurity,

        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [bool]
        $OverwriteDataSources=$true,

        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [bool]
        $OverwriteDatasets=$true,

        [Parameter(ParameterSetName='Target',Mandatory=$false)]
        [Parameter(ParameterSetName='Configuration',Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter(Mandatory=$false)]
        [string] 
        $PackagePath
    )

    if ($Credential) {
        $cred = $Credential.UserName
    }

    Write-Log -Info "Deploying SSRS package '$PackageName' using TargetServerURL '$TargetServerURL', Folder '$TargetFolder', DataSource '$TargetDataSourceFolder', Dataset '$TargetDataSetFolder', Credential '$cred'" -Emphasize

    $configPaths = Get-ConfigurationPaths

    $PackagePath = Resolve-PathRelativeToProjectRoot `
                    -Path $PackagePath `
                    -DefaultPath (Join-Path -Path $configPaths.PackagesPath -ChildPath $PackageName) `
                    -ErrorMsg "Cannot find file '{0}' required for deployment of package '$PackageName'. Please ensure you have run the build and the package exists."
   
    if ($ProjectName) {
        $ProjectPath = Join-Path -Path $PackagePath -ChildPath "$ProjectName.rptproj"
        if (!(Test-Path -LiteralPath $ProjectPath)) {
            throw "Project $ProjectPath doesn't exist"
        } 
    } else {
        $projectFiles = ,(Get-ChildItem -Path $PackagePath | Where-Object {$_.extension -eq ".rptproj"})
        if ($projectFiles.Length -gt 1) {
            throw "Multiple projects found in $PackagePath but project name was not specified."
        }
        $ProjectPath = $projectFiles[0].FullName
    }

    $ProjectRoot = Split-Path -Parent $ProjectPath
    if (!$ProjectRoot) {
        $ProjectRoot = '.'
    }

    [xml]$Project = Get-Content -Path $ProjectPath -ReadCount 0 -Encoding UTF8

    if ($PSCmdlet.ParameterSetName -eq 'Configuration') {
        $Config = Get-SSRSProjectConfiguration -Path $ProjectPath -Configuration $ProjectConfigurationName
        $TargetServerUrl = $Config.ServerUrl
        $TargetFolder = $Config.Folder
        $TargetDataSourceFolder = $Config.DataSourceFolder
        $TargetDataSetFolder = $Config.DataSetFolder
        $OverwriteDataSources = $Config.OverwriteDataSources
        $OverwriteDatasets = $Config.OverwriteDatasets
    }

    $Proxy = New-SSRSWebServiceProxy -Uri $TargetServerURL -Credential $Credential

    $TargetFolder = Format-SSRSFolder -Folder $TargetFolder
    New-SSRSFolder -Proxy $Proxy -Name $TargetFolder
    if ($TargetDataSourceFolder) {
        $TargetDataSourceFolder = Format-SSRSFolder -Folder $TargetDataSourceFolder
        New-SSRSFolder -Proxy $Proxy -Name $TargetDataSourceFolder
    }
    if ($TargetDataSetFolder) {
        $TargetDataSetFolder = Format-SSRSFolder -Folder $TargetDataSetFolder
        New-SSRSFolder -Proxy $Proxy -Name $TargetDataSetFolder
    }

    Write-Log -Info 'Deploying Data Sources'
    $DataSourcePaths = @{}
    $Project.SelectNodes('Project/DataSources/ProjectItem') |
        ForEach-Object {
            if (!$TargetDataSourceFolder) {
                throw "There are DataSources to deploy and TargetDataSourceFolder has not been defined."
            }
            $RdsPath = $ProjectRoot | Join-Path -ChildPath $_.FullPath
    
            $rdsName = Split-Path -Path $RdsPath -Leaf
    
            if ($DataSources -and $DataSources.ContainsKey($rdsName)) {
               $dataSourceDefinition = $DataSources[$rdsName]
            } elseif ($DataSources -and $DataSources.ContainsKey($RdsPath)) {
               $dataSourceDefinition = $DataSources[$RdsPath]
            } else {
               $dataSourceDefinition = $null
            }
    
            $DataSource = New-SSRSDataSource -Proxy $Proxy -RdsPath $RdsPath -Folder $TargetDataSourceFolder -Overwrite $OverwriteDataSources -DataSourceDefinition $dataSourceDefinition
            
            $DataSourcePaths[$DataSource.Name] = $DataSource.Path
        }
    
    Write-Log -Info 'Deploying Datasets'
    $DataSetPaths = @{}
    
    $Project.SelectNodes('Project/DataSets/ProjectItem') |
        ForEach-Object {
            if (!$TargetDataSetFolder) {
                throw "There are DataSets to deploy and TargetDataSetFolder has not been defined."
            }

            $DataSet = $null
            $RsdPath = $ProjectRoot | Join-Path -ChildPath $_.FullPath
            $Name = [System.IO.Path]::GetFileNameWithoutExtension($RsdPath)
            $DataSet = $Proxy.ListChildren("/", $true) | Where-Object { $_.TypeName -eq "DataSet" -and $_.Name -eq $Name }

            if ($DataSet -ne $null) { 
                Write-Log -Info "Dataset $($Name) already exists."
                if (!$OverwriteDatasets) { 
                     Write-Log -Info "'OverwriteDatasets is set to $OverwriteDatasets', dataset $($DataSet.Name) will not be overwritten."
                }
                else {
                     Write-Log -Info "'OverwriteDatasets is set to $OverwriteDatasets', dataset $($DataSet.Name) will be overwritten."
                     $DataSet = New-SSRSDataSet -Proxy $Proxy -RsdPath $RsdPath -Folder $TargetDataSetFolder -DataSourcePaths $DataSourcePaths -Overwrite $OverwriteDatasets
                }
            }
            else {
                Write-Log -Info "Dataset $($Name) does not exist and will be created."
                $DataSet = New-SSRSDataSet -Proxy $Proxy -RsdPath $RsdPath -Folder $TargetDataSetFolder -DataSourcePaths $DataSourcePaths -Overwrite $OverwriteDatasets
            }
            
            $DataSetPaths[$DataSet.Name] = $DataSet.Path
        }
    
    Write-Log -Info 'Deploying Resources'
    $Project.SelectNodes('Project/Reports/ResourceProjectItem') |
        ForEach-Object {
            if ($_.MimeType.StartsWith('image/')) {
                [void](New-SSRSResource -Proxy $Proxy -FilePath $_.FullPath -SourceFolder $ProjectRoot -DestinationFolder $TargetFolder -MimeType $_.MimeType)
            }
        }
    
    Write-Log -Info 'Deploying Reports'
    $Project.SelectNodes('Project/Reports/ProjectItem') |
        ForEach-Object {
            $RdlPath = $ProjectRoot | Join-Path -ChildPath $_.FullPath
            [xml]$Definition = Get-Content -Path $RdlPath -ReadCount 0 -Encoding UTF8
            $NsMgr = New-XmlNamespaceManager -XmlDocument $Definition -DefaultNamespacePrefix 'd'
    
            $RawDefinition = Get-AllBytes -Path $RdlPath
    
            $Name = $_.Name -replace '\.rdl$',''
    
            $DescProp = New-Object -TypeName SSRS.ReportingService2010.Property
            $DescProp.Name = 'Description'
            $DescProp.Value = ''
            $HiddenProp = New-Object -TypeName SSRS.ReportingService2010.Property
            $HiddenProp.Name = 'Hidden'
            $HiddenProp.Value = 'false'
            $Properties = @($DescProp, $HiddenProp)
        
            $Xpath = 'd:Report/d:Description'
            $DescriptionNode = $Definition.SelectSingleNode($Xpath, $NsMgr)
        
            if ($DescriptionNode) {
                $DescProp.Value = $DescriptionNode.Value
            }
        
            if ($Name.StartsWith('_')) {
                $HiddenProp.Value = 'true'
            }
        
            [void](New-SSRSCatalogItem -Proxy $Proxy -ItemType 'Report' -Name $Name -Parent $TargetFolder -Overwrite $true -Definition $RawDefinition -Properties $Properties)
    
            $Xpath = 'd:Report/d:DataSources/d:DataSource/d:DataSourceReference/..'
            $ds = $Definition.SelectNodes($Xpath, $NsMgr) |
                ForEach-Object {
                    $DataSourcePath = $DataSourcePaths[$_.DataSourceReference]
                    if (-not $DataSourcePath) {
                        throw "Invalid data source reference '$($_.DataSourceReference)' in $RdlPath"
                    }
                    $Reference = New-Object -TypeName SSRS.ReportingService2010.DataSourceReference
                    $Reference.Reference = $DataSourcePath
                    $DataSource = New-Object -TypeName SSRS.ReportingService2010.DataSource
                    $DataSource.Item = $Reference
                    $DataSource.Name = $_.Name
                    $DataSource
                }
            if ($ds) {        
                Set-SSRSItemDataSources -Proxy $Proxy -ItemPath ($TargetFolder + '/' + $Name) -DataSources $ds
            }
            
            $Xpath = 'd:Report/d:DataSets/d:DataSet/d:SharedDataSet/d:SharedDataSetReference/../..'
            $References = $Definition.SelectNodes($Xpath, $NsMgr) |
                ForEach-Object {
                    $DataSetPath = $DataSetPaths[$_.SharedDataSet.SharedDataSetReference]
                    if ($DataSetPath) {
                        $Reference = New-Object -TypeName SSRS.ReportingService2010.ItemReference
                        $Reference.Reference = $DataSetPath
                        $Reference.Name = $_.Name
                        $Reference
                    }
                }
            if ($References) {
                Set-SSRSItemReferences -Proxy $Proxy -ItemPath ($TargetFolder + '/' + $Name) -ItemReferences $References
            }
        }
    
        if ($ReportItemsSecurity) {
            Write-Log -Info 'Deploying report item security policies'
            foreach ($itemSecurity in $ReportItemsSecurity.GetEnumerator()) {
                Set-SSRSItemSecurity -Proxy $Proxy -ItemPath $itemSecurity.Key -GroupUserNameAndRoles $itemSecurity.Value
            }
        }
}
