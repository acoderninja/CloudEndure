$script:URL = "https://console.cloudendure.com/api"
$script:Installer = "https://console.cloudendure.com/installer_win.exe"
$script:ProfileLocation = "$env:USERPROFILE\.cloudendure\credentials"

[System.Collections.Hashtable]$script:AWSRegionMap = @{
	"Generic" = "f54420d5-3de4-40bb-b35b-33d32ad8c8ef";
	"AWS US East (Northern Virginia)" = "71fbc661-a3a8-4315-bcf9-3db3353a6ef8";
	"AWS US West (Northern California)" = "959d856b-3730-48c2-84ba-a509497b2085";
	"AWS US West (Oregon)" = "31cc9e94-58af-4920-9cd7-db6a45f28fd4";
	"AWS EU (Ireland)" = "114b110d-00ad-48d4-a930-90cb3f8cde2e";
	"AWS EU (Frankfurt)" = "349db794-4bfc-4fc5-a733-659081d6729d";
	"AWS Asia Pacific (Singapore)" = "fc89da33-0eab-4602-8e4d-8c35b0ad8f65";
	"AWS Asia Pacific (Sydney)" = "4b4a4ff4-e5d9-4b62-8e7c-7210c9ea2be2";
	"AWS Asia Pacific (Tokyo)" = "acce3f71-3e7e-48db-bc5c-84d57f84f919";
	"AWS South America (Sao Paulo)" = "5dbb0a54-3361-4a6b-9dcb-1a1f87f4e1a2";
	"AWS US East (Ohio)" = "2941040c-a410-4bec-8842-566da8ca7729";
	"AWS Asia Pacific (Mumbai)" = "e5dfe786-736f-4f15-a737-7915e1a98349";
	"AWS Asia Pacific (Seoul)" = "1c805747-322d-4f04-b0cc-022a63baa824";
	"AWS EU (London)" = "0191fdf5-779f-4a54-a0ce-6e3b5157ce36";
	"AWS Canada (Central)" = "910a2cd6-0298-4c9b-82f5-74d6bd265211"
}

[System.Collections.Hashtable]$script:CloudIds = @{
	"AWS" = "6849e59c-29f5-4e10-a459-9d8584c7524b";
	"GENERIC" = "4e665c91-6dbc-4802-9832-85990d048852";
	"VCENTER" = "df35a75f-3b21-4161-aae0-4942d6e3b5f4";
	"On-Premises" = "00000000-0000-0000-0000-000000000000";
	"GCP" = "00000000-0000-0000-0000-000000000000";
	"Azure" = "00000000-0000-0000-0000-000000000000"
}

[System.Collections.Hashtable]$script:IdToCloudMap = @{
	"6849e59c-29f5-4e10-a459-9d8584c7524b" = "AWS";
	"4e665c91-6dbc-4802-9832-85990d048852" = "GENERIC";
	"df35a75f-3b21-4161-aae0-4942d6e3b5f4" = "VCENTER";
	"00000000-0000-0000-0000-000000000000" = "On-Premises";
	"GCP" = "00000000-0000-0000-0000-000000000001";
	"Azure" = "00000000-0000-0000-0000-000000000002"
}

# This is hashtable of hashtables
[System.Collections.Hashtable]$script:Sessions = @{}

[System.String[]]$script:CommonParams = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters + @("PassThru", "Force", "Session", "ProjectId")
[System.String]$script:AllParameterSets = "__AllParameterSets"

#region Private Functions

Function Get-CESessionOrDefault {
	[CmdletBinding()]
	Param(
		[Parameter(Position = 0)]
		[System.String]$Session
	)

	Begin {

	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -eq $null) 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}

		Write-Output -InputObject $SessionInfo
	}

	End {

	}
}

Function Invoke-CERequest {
	[CmdletBinding()]
	Param(
		[Parameter(ParameterSetName = "Path")]
		[ValidatePattern("^/.*$")]
		[System.String]$Path,

		[Parameter(ParameterSetName = "Uri")]
		[ValidateNotNullOrEmpty()]
		[System.String]$Uri,

		[Parameter(Mandatory = $true)]
		[Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

		[Parameter()]
		[System.String]$Session,

		[Parameter()]
		[ValidateRange(100, 599)]
		[System.Int32]$ExpectedResponseCode = 200,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$Body = [System.String]::Empty,

		[Parameter()]
		[ScriptBlock]$ErrorHandling = $null,

		[Parameter()]
		[System.Object[]]$ErrorHandlingArgs = @()
	)

	Begin {
	}

	Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		[System.Int32]$StatusCode = 0
		$Reason = ""
		$Splat = @{}

		if (-not [System.String]::IsNullOrEmpty($Body))
		{
			$Splat.Add("Body", $Body)
		}

		switch ($PSCmdlet.ParameterSetName)
		{
			"Path" {
				$Splat.Add("Path", $Path)
				break
			}
			"Uri" {
				$Splat.Add("Uri", $Uri)
				break
			}
		}

		# If a response generates a 300+ http response 
		# it will set the error message
		# Hashtable has WebResponse, StatusCode, and ErrorMessage properties
		[System.Collections.Hashtable]$Result = Invoke-WebRequestWithBasicErrorHandling -Method $Method -Session $Session @Splat

		if ($ErrorHandling -eq $null)
		{
			if ($Result["StatusCode"] -eq $ExpectedResponseCode)
			{
				Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result["WebResponse"].Content))
			}
			else
			{
				throw $Result["ErrorMessage"]
			}
		}
		else
		{
			& $ErrorHandling $Result["StatusCode"] $Result["WebResponse"].Content $Result["ErrorMessage"] $ErrorHandlingArgs
		}
	}

	End {
	}
}

Function Invoke-WebRequestWithBasicErrorHandling {
	[CmdletBinding(DefaultParameterSetName = "Path")]
	Param(
		[Parameter(ParameterSetName = "Path", Mandatory = $true)]
		[ValidatePattern("^/.*$")]
		[System.String]$Path,

		[Parameter(ParameterSetName = "Uri", Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$Uri,

		[Parameter(Mandatory = $true)]
		[Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

		[Parameter()]
		[System.String]$Session,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$Body = [System.String]::Empty,

		[Parameter(ParameterSetName = "Uri")]
		[Switch]$Login
	)

	Begin {

		# No existing session info for a new session
		if (-not $Login)
		{
			$SessionInfo = Get-CESessionOrDefault -Session $Session
		}

		[System.Int32]$StatusCode = 0
		$Reason = ""
		$Splat = @{}

		if (-not [System.String]::IsNullOrEmpty($Body))
		{
			$Splat.Add("Body", $Body)
			$Splat.Add("ContentType", "application/json")
		}

		switch ($PSCmdlet.ParameterSetName)
		{
			"Path" {
				$Splat.Add("Uri", "$($SessionInfo.Url)$Path")
				break
			}
			"Uri" {
				$Splat.Add("Uri", $Uri)
				break
			}
		}

		if ($Login)
		{
			$Splat.Add("SessionVariable", "WebSession")
		}

		try {
			[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
			[Microsoft.PowerShell.Commands.WebResponseObject]$Result = Invoke-WebRequest -Method $Method -WebSession $SessionInfo.WebSession -UseBasicParsing -ErrorAction Stop @Splat
			$StatusCode = $Result.StatusCode
			$Reason = $Result.StatusDescription
			Write-Verbose -Message $Result.Content
		}
		catch [System.Net.WebException] {
			[System.Net.WebException]$Ex = $_.Exception

			if ($Ex.Response -eq $null)
			{
				$Reason = "$($Ex.Status): $($Ex.Message)"
				$StatusCode = 500
			}
			else
			{
				[System.Net.HttpWebResponse]$Response = $Ex.Response
				$StatusCode = [System.Int32]$Response.StatusCode
			
				[System.IO.Stream]$Stream = $Response.GetResponseStream()
				[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
				[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
				$Content = $Reader.ReadToEnd()

				$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
			}
		}
		catch [Exception]  {
			$Reason = $_.Exception.Message
		}

		$ErrorMessage = ""

		if ($StatusCode -ge 300)
		{
			$ErrorMessage = "$StatusCode : $Reason$(if (-not [System.String]::IsNullOrEmpty($Result.Content)) {"`n$($Result.Content)"})"
		}

		$ReturnData = @{"WebResponse" = $Result;
			"StatusCode" = $StatusCode;
			"ErrorMessage" = $ErrorMessage
		}

		if ($Login)
		{
			$ReturnData.Add("SessionVariable", $WebSession)
		}

		Write-Output -InputObject $ReturnData
	}
}

Function Convert-ParametersToHashtable {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
        [ValidateNotNull()]
		[System.Collections.Generic.Dictionary[System.String, System.Management.Automation.ParameterMetadata]]$Parameters,

		[Parameter()]
        [ValidateNotNullOrEmpty()]
		[System.String]$ParameterSetName = $script:AllParameterSets,

		[Parameter()]
        [ValidateNotNull()]
		[System.Management.Automation.RuntimeDefinedParameterDictionary]$RuntimeParameterDictionary,

		[Parameter(Mandatory = $true)]
        [ValidateNotNull()]
		[System.Collections.Generic.Dictionary[System.String, System.Object]]$BoundParameters,

		[Parameter()]
		[Switch]$IncludeAll,

		[Parameter(ParameterSetName = "Defaults")]
		[Switch]$IncludeDefaults,

		[Parameter(ParameterSetName = "Defaults", Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$FunctionName
	)

	Begin {
	}

	Process {
		$Params = @{}
		$Output = @{}

		foreach ($Item in $Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key)})
        {
			[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
            $Params.Add($Item.Key, $Sets)
        }

        if ($RuntimeParameterDictionary -ne $null)
        {
		    # Get the dynamic parameters, iterate on each
            $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
            
			    # Get the parameter
			    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

			    # If the parameter is set and it hasn't already been added
                if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                {
				    # Get the parameter name and its parameter sets
				    [System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
                    $Params.Add($Param.Name, $ParameterSets)
                }
            }
        }

		# Get the parameters for the command
		foreach ($Item in $Params.GetEnumerator())
		{
			# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
			if ($Item.Value.Contains($ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
			{
				$Add = $false
				$Value = $null

				# Check to see if it was supplied by the user
				if ($BoundParameters.ContainsKey($Item.Key))
				{
					$Add = $true
					$Value = $BoundParameters[$Item.Key]
				}				
				else
				{
					# If not supplied, and we're including defaults, see if it has a default value
					if ($IncludeDefaults)
					{
						if (Test-ParameterHasDefaultValue -FunctionName $FunctionName -Parameter $Item.Key)
						{
							$Add = $true
							$Value = Get-ParameterDefaultValue -FunctionName $FunctionName -Parameter $Item.Key
						}
					}
					elseif ($IncludeAll)
					{
						# Check this since it may have been added with a default value already
						if ($Add -eq $false)
						{
							$Name = $Parameters[$Item.Key].ParameterType.FullName
							$Add = $true
							Set-Variable $Value -Scope 1 -Value (([System.Object]$V) -as ($Name -as [Type]))
						}
					}
				}

				if ($Add)
				{
					$Output.Add($Item.Key.Substring(0, 1).ToLower() + $Item.Key.Substring(1), $Value)
				}
			}
		}

		Write-Output -InputObject $Output
	}

	End {
	}
}

Function Get-ParameterDefaultValue {
	<#

	#>
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[System.String]$FunctionName,
		
		[Parameter(Mandatory = $true, Position = 1)]
		[ValidateNotNullOrEmpty()]
		[System.String]$Parameter
	)

    Begin {
    }

    Process {
        if (-not (Test-ParameterHasDefaultValue -FunctionName $FunctionName -Parameter $Parameter))
        {
            throw "The parameter $Parameter in $FunctionName does not have a default value."
        }
	
		$Ast = (Get-Command $FunctionName).ScriptBlock.Ast
		
		$Select = @{ n = "Name"; e = { $_.Name.VariablePath.UserPath } },
		@{ n = "Value"; e = { $_.DefaultValue.Extent.Text -replace "`"|'" } }
		
        $Result = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true) | 
            Select-Object $Select | 
            Where-Object {$_.Name -ieq $Parameter } | 
            Select-Object -ExpandProperty Value
       
		Write-Output -InputObject (Invoke-Expression $Result)
    }

    End {
    }
}

Function Test-ParameterHasDefaultValue {
	<#

	#>
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[System.String]$FunctionName,
		
		[Parameter(Mandatory = $true, Position = 1)]
		[ValidateNotNullOrEmpty()]
		[System.String]$Parameter
	)
	Begin {
    }

    Process {
		$Ast = (Get-Command $FunctionName).ScriptBlock.Ast
		
		$Select = @{ n = "Name"; e = { $_.Name.VariablePath.UserPath } },
		@{ n = "Value"; e = { $_.DefaultValue.Extent.Text -replace "`"|'" } }
		
        $Result = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true) | 
            Where-Object { $_.DefaultValue } |
            Select-Object $Select | 
            Where-Object { $_.Name -ieq $Parameter } 

		Write-Output -InputObject ($Result -ne $null)
		
	}
	
    End {
	}
}

#endregion

#region Profiles 

Function New-CEProfile {
	<#
		.SYNOPSIS
			Saves a new CloudEndure profile.

		.DESCRIPTION
			The cmdlet saves a username and password (encrypted using the Windows DPAPI under the current user's context) to a file at a specified profile location.
			The profile credentials can be called later during the New-CESession cmdlet to simplify remembering credentials.

		.PARAMETER Credential
			The credentials to save.

		.PARAMTER ProfileName
			The name of the profile.

		.PARAMETER ProfileLocation
			Specify a non-default location to store the profile file. This defaults to $env:USERPROFILE\.cloudendure\credentials

		.EXAMPLE
			New-CEProfile -ProfileName "MyCEProfile" -Credential (New-Object -TypeName System.Management.Automation.PSCredential("john.smith@contoso.com", (ConvertTo-SecureString -String "My$ecurEP@$$w0Rd" -AsPlainText -Force))

			This saves a new profile named MyCEProfile with the specified credentials.

		.INPUTS
			System.Management.Automation.PSCredential
				
		.OUTPUTS
			None

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/11/2019
	#>
	# Default to ApiToken so when someone specifies the ApiToken parameter
	# it won't be confused on whether or not credential is required as well
	[CmdletBinding(DefaultParameterSetName = "ApiToken")]
	[OutputType()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "Creds")]
		[ValidateNotNull()]
		[System.Management.Automation.Credential()]
		[System.Management.Automation.PSCredential]$Credential = [PSCredential]::Empty,

		[Parameter(Mandatory = $true, ParameterSetName = "ApiToken")]
		[Parameter(ParameterSetName = "Creds")]
		[ValidateNotNullOrEmpty()]
		[System.String]$ApiToken = [System.String]::Empty,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileName,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileLocation = [System.String]::Empty
	)

	Begin {
	}

	Process {
		if ([System.String]::IsNullOrEmpty($ProfileLocation)) 
		{
			$ProfileLocation = $script:ProfileLocation
		}

		Write-Verbose -Message "Using profile location $ProfileLocation."

		if (-not (Test-Path -Path $ProfileLocation -PathType Leaf))
		{
			Write-Verbose -Message "Creating new credentials file at $ProfileLocation."
			New-Item -Path $ProfileLocation -ItemType File -Force
		}
		
		switch ($PSCmdlet.ParameterSetName)
		{
			"Creds" {
				$CEProfile = @{"username" = $Credential.UserName; 
					"password" = ConvertFrom-SecureString -SecureString $Credential.Password; 
					"apitoken" = $ApiToken.Replace("-", "")}

				break
			}
			"ApiToken" {
				$CEProfile = @{"username" = ""; 
					"password" = ""; 
					"apitoken" = $ApiToken.Replace("-", "")}
				break
			}
			default {
				throw "$($PSCmdlet.ParameterSetName) is not a recognized parameter set."
			}
		}

		# This will store the password encrypted with the Windows DPAPI using the user's credentials
		
		$Content = Get-Content -Path $ProfileLocation -Raw

		if ($Content -ne $null -and -not [System.String]::IsNullOrEmpty($Content))
		{
			[PSCustomObject]$Json = ConvertFrom-Json -InputObject $Content
		}
		else
		{
			[PSCustomObject]$Json = [PSCustomObject]@{}
		}

		if ((Get-Member -InputObject $Json -Name $ProfileName -MemberType Properties) -ne $null) 
		{
			Write-Warning -Message "The profile $ProfileName is being overwritten with new data."
			$Json.$ProfileName =  $CEProfile
		}
		else 
		{
			$Json | Add-Member -MemberType NoteProperty -Name $ProfileName -Value $CEProfile
		}

		Set-Content -Path $ProfileLocation -Value (ConvertTo-Json -InputObject $Json)
		Write-Verbose -Message "Successfully saved credentials."
	}

	End {
	}
}

Function Get-CEProfile {
	<#
		.SYNOPSIS
			Gets profile information.

		.DESCRIPTION
			This cmdlet retrieves a list of available profile names if no profile name is specified. If a profilename is specified, a PSCredential object is returned back if the profile is found.

		.PARAMETER ProfileName
			The name of the profile to retrieve. If this is not specified, a list of available profile names is returned.

		.PARAMETER ProfileLocation
			The location of the profile credential data. This defaults to $env:USERPROFILE\.cloudendure\credentials.

		.EXAMPLE
			Get-CEProfile
			
			This returns a list of available profiles.

		.EXAMPLE
			Get-CEProfile -ProfileName MyCEProfile

			This returns a PSCredential object with the credentials stored as MyCEProfile using the New-CEProfile cmdlet.

		.INPUTS
			System.String

		.OUTPUTS
			System.String[] or PSCustomObject

			If no profile is specified, an array of profile names is returned. If the profile name is specified, the a PSCustomObject with a PSCredential and API Token string are retured.

			{
				"credential" : PSCredential,
				"apitoken" : "tokenstring"
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/11/2019
	#>
	[CmdletBinding()]
	[OutputType([PSCustomObject], [System.String[]])]
	Param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileName = [System.String]::Empty,

		[Parameter(Position = 1)]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileLocation = [System.String]::Empty
	)

	Begin {
	}

	Process {
		if ([System.String]::IsNullOrEmpty($ProfileLocation)) 
		{
			$ProfileLocation = $script:ProfileLocation
		}

		if (-not (Test-Path -Path $ProfileLocation -PathType Leaf))
		{
			Write-Warning -Message "No profile data stored at $ProfileLocation"
			Exit
		}

		$Content = Get-Content -Path $ProfileLocation -Raw

		if ($Content -ne $null -and -not [System.String]::IsNullOrEmpty($Content))
		{
			[PSCustomObject]$Json = ConvertFrom-Json -InputObject $Content
		}
		else
		{
			[PSCustomObject]$Json = [PSCustomObject]@{}
		}

		if (-not [System.String]::IsNullOrEmpty($ProfileName))
		{
			# This is the profile data including the credential and/or api token
			if (-not ($Json | Get-Member -MemberType Properties -Name $ProfileName))
			{
				throw "A profile with the name $ProfileName could not be found in $ProfileLocation."
			}

			$Value = $Json.$ProfileName

			if (
				# If either username or password are missing
				(
					(-not ($Value | Get-Member -MemberType Properties -Name username)) -or
					(-not ($Value | Get-Member -MemberType Properties -Name password))
				) -and
				# And api token is missing or empty, throw an exception
				(
					(-not ($Value | Get-Member -MemberType Properties -Name apitoken)) -or
					($Value.apitoken -eq [System.String]::Empty)
				)
			)
			{
				throw "Profile $ProfileName does not have properly configured credentials.`n$($Value | ConvertTo-Json)"
			}
				
			# Convert the stored data back to a PSCredential object
			$Creds = New-Object -TypeName System.Management.Automation.PSCredential($Json.$ProfileName.username, (ConvertTo-SecureString -String $Json.$ProfileName.password))
			[PSCustomObject]$CEProfile = [PSCustomObject]@{"credential" = $Creds; "apitoken" = ""}

			if (-not [System.String]::IsNullOrEmpty($Json.$ProfileName.apitoken))
			{
				$CEProfile.apitoken = Convert-SecureStringToString -SecureString (ConvertTo-SecureString -String $Json.$ProfileName.apitoken)
			}

			Write-Output -InputObject $CEProfile
		}
		else 
		{
			# This will return all of the "keys" which are the profile names
			Write-Output -InputObject ($Json | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name)
		}	
	}

	End {
	}
}

Function Update-CEProfile {
	<#
		.SYNOPSIS 
			Updates an existing CE Profile.

		.DESCRIPTION
			Updates an existing CE Profile with a new username and password and/or API Token.

		.PARAMETER Credential
			The credentials to save.

		.PARAMETER ApiToken
			The API Token to save.

		.PARAMTER ProfileName
			The name of the profile.

		.PARAMETER ProfileLocation
			Specify a non-default location to store the profile file. This defaults to $env:USERPROFILE\.cloudendure\credentials

		.EXAMPLE
			Update-CEProfile -ProfileName MyCEProfile -Credential -Credential (New-Object -TypeName System.Management.Automation.PSCredential("john.smith@contoso.com", (ConvertTo-SecureString -String "MyNEW$ecurEP@$$w0Rd" -AsPlainText -Force))

		.INPUTS
			None
				
		.OUTPUTS
			None

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/11/2019
	#>
	[CmdletBinding()]
	[OutputType()]
	Param(
		[Parameter()]
		[ValidateNotNull()]
		[System.Management.Automation.Credential()]
		[System.Management.Automation.PSCredential]$Credential = [PSCredential]::Empty,

		[Parameter()]
		[ValidateNotNull()]
		[System.String]$ApiToken,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileName,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileLocation = [System.String]::Empty
	)

	Begin {
	}

	Process {
		if ([System.String]::IsNullOrEmpty($ProfileLocation)) 
		{
			$ProfileLocation = $script:ProfileLocation
		}

		Write-Verbose -Message "Using profile location $ProfileLocation."

		if (-not (Test-Path -Path $ProfileLocation -PathType Leaf))
		{
			Write-Warning -Message "Profile data could not be found at $ProfileLocation."
			Exit
		}

		$Content = Get-Content -Path $ProfileLocation -Raw

		if ($Content -ne $null -and -not [System.String]::IsNullOrEmpty($Content))
		{
			[PSCustomObject]$Json = ConvertFrom-Json -InputObject $Content
		}
		else
		{
			throw "No profiles found in $ProfileLocation."
		}

		# This is the profile data including the credential and/or api token
		if (-not ($Json | Get-Member -MemberType Properties -Name $ProfileName))
		{
			throw "A profile with the name $ProfileName could not be found in $ProfileLocation."
		}

		$Value = $Json.$ProfileName

		if ($Credential -ne [System.Management.Automation.PSCredential]::Empty)
		{
			if (-not ($Value | Get-Member -MemberType NoteProperty -Name username))
			{
				$Value | Add-Member -Name username -MemberType NoteProperty -Value ""
			}

			if (-not ($Value | Get-Member -MemberType NoteProperty -Name password))
			{
				$Value | Add-Member -Name password -MemberType NoteProperty -Value ""
			}

			$Value.username = $Credential.UserName
			$Value.password = ConvertFrom-SecureString -SecureString $Credential.Password
		}

		if (-not [System.String]::IsNullOrEmpty($ApiToken))
		{
			if (-not ($Value | Get-Member -MemberType NoteProperty -Name apitoken))
			{
				$Value | Add-Member -Name apitoken -MemberType NoteProperty -Value ""
			}

			$Value.apitoken = ConvertTo-SecureString -String $ApiToken.Replace("-", "") -AsPlainText -Force | ConvertFrom-SecureString
		}

		$Json.$ProfileName = $Value

		Set-Content -Path $ProfileLocation -Value (ConvertTo-Json -InputObject $Json)
		Write-Verbose -Message "Successfully saved credentials."
	}

	End {
	}
}

Function Remove-CEProfile {
	<#
		.SYNOPSIS
			Removes a CE profile.

		.DESCRIPTION
			This cmdlet retrieves the specified profile and deletes it from the credentials file.

		.PARAMETER ProfileName
			The name of the profile to remove.

		.PARAMETER ProfileLocation
			The location of the profile credential data. This defaults to $env:USERPROFILE\.cloudendure\credentials.

		.PARAMETER PassThru
			If specified, the deleted profile is returned as a PSCredential object.

		.EXAMPLE
			Remove-CEProfile -ProfileName "MyCEProfile"

			Removes the MyCEProfile profile.

		.INPUTS
			System.String

		.OUTPUTS
			None or System.Management.Automation.PSCredential

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([System.Management.Automation.PSCredential])]
	Param(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileName = [System.String]::Empty,

		[Parameter(Position = 1)]
		[ValidateNotNullOrEmpty()]
		[System.String]$ProfileLocation = [System.String]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force
	)

	Begin {
	}

	Process {
		if ([System.String]::IsNullOrEmpty($ProfileLocation)) 
		{
			$ProfileLocation = $script:ProfileLocation
		}

		if (Test-Path -Path $ProfileLocation -PathType Leaf)
		{
			$Content = Get-Content -Path $ProfileLocation -Raw

			if ($Content -ne $null -and -not [System.String]::IsNullOrEmpty($Content))
			{
				[PSCustomObject]$Json = ConvertFrom-Json -InputObject $Content
				$Value = $Json | Get-Member -MemberType Properties -Name $ProfileName
				
				if ($Value -ne $null)
				{
					# Convert the stored data back to a PSCredential object
					$Creds = New-Object -TypeName System.Management.Automation.PSCredential($Json.$ProfileName.username, (ConvertTo-SecureString -String $Json.$ProfileName.password))

					$ConfirmMessage = "You are about to delete profile $ProfileName."
					$WhatIfDescription = "Deleted profile $ProfileName"
					$ConfirmCaption = "Delete CE Profile"

					if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
					{
						# This returns void, so do it first, then pass the $Json variable
						$Json.PSObject.Properties.Remove($ProfileName)
						Set-Content -Path $ProfileLocation -Value (ConvertTo-Json -InputObject $Json)

						if ($PassThru) 
						{
							Write-Output -InputObject $Creds
						}
					}
				}
				else
				{
					Write-Warning -Message "No profile matching $ProfileName in $ProfileLocation"
				}
			}
		}
		else
		{
			Write-Warning -Message "No profile data stored at $ProfileLocation"
		}
	}

	End {
	}
}

#endregion

#region Sessions

Function New-CESession {
    <#
        .SYNOPSIS
            Establishes a new session with the CE console

        .DESCRIPTION
            The cmdlet establishes a new session with the CE console and saves the session information to local script variables. These can be cleared with the Remove-CESession cmdlet.

        .PARAMETER Version
            The version of the API this session will use. This defaults to "LATEST".

			This parameter is deprecated, the CE API set handles selecting the correct version for you based on your account and this parameter has no effect.

        .PARAMETER Credential
            The credential to use to connect to the CE console.

		.PARAMETER ApiToken
			The user API Token to use to login.

		.PARAMETER GoogleOAuthCode
			The Google OAuth code used to login.

		.PARAMETER ProfileName
			The name of the profile to use.

        .PARAMETER PassThru
            If specified, the session unique identifier, the CE username, will be returned. This can be specified directly to follow-on cmdlets to specify which account the cmdlet targets.

        .EXAMPLE
            New-CESession -Credential (New-Object -TypeName System.Management.Automation.PSCredential("myfirstmigration@cloudendure.com", (ConvertTo-SecureString -String "mySecureP@$$w0rd" -AsPlainText -Force)))

            Establishes a new session to CE with the supplied email address and password. The session information is stored in script variables.

        .INPUTS
            None

        .OUTPUTS
            None or System.String

			If PassThru is specified the username being used to store the session data is returned.

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
    #>
    [CmdletBinding(DefaultParameterSetName = "Profile")]
    [OutputType([System.String])]
	Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Credential")]
		[ValidateNotNull()]
		[System.Management.Automation.Credential()]
		[System.Management.Automation.PSCredential]$Credential = [System.Management.Automation.PSCredential]::Empty,

		[Parameter(Mandatory = $true, ParameterSetName = "ApiToken")]
		[ValidateNotNullOrEmpty()]
		[System.String]$ApiToken,

		[Parameter(Mandatory = $true, ParameterSetName = "GoogleOAuth")]
		[ValidateNotNullOrEmpty()]
		[System.String]$GoogleOAuthCode,
 
        [Parameter()]
        [Switch]$PassThru
	)

	DynamicParam {
		if (
			($Credential -eq $null -or $Credential -eq [System.Management.Automation.PSCredential]::Empty) -and 
			[System.String]::IsNullOrEmpty($ApiToken) -and
			[System.String]::IsNullOrEmpty($GoogleOAuthCode)
		)
		{
			$Params = @(
				@{
					"Name" = "ProfileName";
					"Type" = [System.String];
					"ValidateSet" = (Get-CEProfile);
					"ParameterSets" = @("Profile");
					"Mandatory" = $true;
					"ValidateNotNullOrEmpty" = $true
				},
				@{
					"Name" = "ProfileLocation";
					"Type" = [System.String];
					"ParameterSets" = @("Profile");
					"ValidateNotNullOrEmpty" = $true
				}
			)

			$Params | ForEach-Object {
				New-Object PSObject -Property $_ 
			} | New-DynamicParameter
		}
	}

	Begin {
	}

	Process {
		$Body = @{}

		switch ($PSCmdlet.ParameterSetName)
		{
			"ApiToken" {
				$Body.Add("userApiToken", $ApiToken)
				break
			}
			"Profile" {
				$Splat = @{"ProfileName" = $PSBoundParameters["ProfileName"]}

				if (-not [System.String]::IsNullOrEmpty($PSBoundParameters["ProfileLocation"]))
				{
					$Splat.Add("ProfileLocation", $PSBoundParameters["ProfileLocation"])
				}

				# This will safety check to make sure the profile has
				# credentials, it will throw an exception if the profile does not
				$Creds = Get-CEProfile @Splat

				if ($Creds -eq $null)
				{
					throw "Could not find a profile named $($PSBoundParameters["ProfileName"])."
				}

				if (($Creds | Get-Member -MemberType Properties -Name apitoken) -and (-not [System.String]::IsNullOrEmpty($Creds.apitoken)))
				{
					$Body.Add("userApiToken", $Creds.apitoken)
				}
				else
				{
					$Credential = $Creds.credential
					$Body.Add("username", $Credential.UserName) 
					$Body.Add("password", (Convert-SecureStringToString -SecureString $Credential.Password))
				}

				break
			}
			"Credential" {
				$Body.Add("username", $Credential.UserName) 
				$Body.Add("password", (Convert-SecureStringToString -SecureString $Credential.Password))
				break
			}
			"GoogleOAuth" {
				$Body.Add("googleOauthCode", $GoogleOAuthCode)
				break
			}
			default {
				throw "Unrecognized parameter set name $($PSCmdlet.ParameterSetName)."
			}
		}

		# Always logon to latest
        [System.String]$Uri = "$script:URL/latest/login"

		<#
			{
				"username": "user@example.com",
				"loginToken": "string",
				"userApiToken": "string",
				"agentInstallationToken": "string",
				"password": "pa$$word",
				"accountIdentifier": "string",
				"googleOauthCode": "string"
			}
		#>
		[System.Collections.Hashtable]$Data = Invoke-WebRequestWithBasicErrorHandling -Uri $Uri -Method Post -Body (ConvertTo-Json -InputObject $Body) -Login
		[Microsoft.PowerShell.Commands.WebResponseObject]$Result = $Data["WebResponse"]

		switch ($Result.StatusCode)
		{
			200 {
				$Version = $Result.Headers["X-CloudEndure-Version"]
				
				# Login can return a redirect to a specific API version endpoint, grab this redirected endpoint from the response and save
				# it to use on all subsequent requests
				[System.String]$Url = $Result.BaseResponse.ResponseUri.ToString().Substring(0,  $Result.BaseResponse.ResponseUri.ToString().LastIndexOf("/"))

				if ($Url.EndsWith("latest"))
				{
					$Url = $Url.Substring(0, $Url.LastIndexOf("/")) + "/$Version"
				}

				[Microsoft.PowerShell.Commands.WebRequestSession]$WebSession = $Data["SessionVariable"]

				<#
					{
						"username": "user@example.com",
						"status": "PENDING",
						"account": "string",
						"roles": [
							"USER"
						],
						"settings": {
							"sendNotifications": {
								"projectIDs": [
											"string"
								]
							}
						},
						"apiToken": "string",
						"hasPassword": true,
						"termsAccepted": true,
						"id": "string",
						"selfLink": "string"
					}
				#>
				$LoginResponse = ConvertFrom-Json -InputObject $Result.Content

				# Update Websession variable to persist credentials and headers
				if ($Credential -ne [System.Management.Automation.PSCredential]::Empty)
				{
					$WebSession.Credentials = $Credential
				}

				# Add functionality for new XSRF token included in login for v3, which now must be presented
				# in the header of each request
				[System.Net.CookieCollection]$Cookies = $WebSession.Cookies.GetCookies($Url)
				[System.Net.Cookie]$MatchingCookie = $Cookies | Where-Object {$_.Name -ieq "XSRF-TOKEN"} | Select-Object -First 1

				if ($MatchingCookie -ne $null)
				{
					$WebSession.Headers.Add("X-XSRF-TOKEN", $MatchingCookie.Value)
				}

				#[System.Collections.Hashtable]$Session = @{Session = $WebSession; ProjectId = $Summary.Projects.Items[0].Id; DefaultProject = $Summary.Projects.Items[0]; DefaultCloudCredentials = $Summary.Projects.Items[0].CloudCredentialsIDs[0]; User = $Summary.User; }	
				[System.Collections.Hashtable]$Session = @{
					WebSession = $WebSession; 
					Url = $Url; 
					DefaultProjectId = "";
					UserId = "";
					DefaultCloudCredentialsId = "";
					User = $LoginResponse; 
					Version = $Version 
				}	

				if ($script:Sessions.ContainsKey($LoginResponse.Username)) {
					$script:Sessions.Set_Item($LoginResponse.Username.ToLower(), $Session)
				}
				else {
					$script:Sessions.Add($LoginResponse.Username.ToLower(), $Session)
				}

				# Set Project Id Defaults
				$ExtendedInfo = Get-CEAccountExtendedInfo -Session $LoginResponse.Username.ToLower()

				$Session["DefaultProjectId"] = $ExtendedInfo.projects.items[0].id
				$Session["UserId"] = $ExtendedInfo.user.id
				$Session["DefaultCloudCredentialsId"] = $ExtendedInfo.projects.items[0].cloudCredentialsIDs[0]
				$script:Sessions.Set_Item($LoginResponse.Username.ToLower(), $Session)

				if ($PassThru) {
					Write-Output -InputObject $LoginResponse.Username.ToLower()
				}
	
				break
			}
			401 {
				throw "The login credentials provided cannot be authenticated"
			}
			402 {
				throw "There is no active license configured for this account (A license must be purchased or extended)." 
			}
			429 {
				throw "Authentication failure limit has been reached. The service will become available for additional requests after a timeout."
			}
			default {
				throw "The login failed for an unknown reason: $($Data["ErrorMessage"])"
			}
		}
	}

	End {
	}
}

Function Get-CESession {
	<#
        .SYNOPSIS
            Gets stored CE session information.

        .DESCRIPTION
            The cmdlet retrieves an established CE session by its Id, or lists all active sessions. If a session name is supplied and cannot be found this function returns null.

        .PARAMETER Session
            Specifies the unique identifier of the session to query. If this parameter is not specified, all stored sessions are returned.

        .EXAMPLE
            Get-CESession

            Gets all CE session information stored in the script variable.

        .INPUTS
            None or System.String

        .OUTPUTS
            System.Collections.Hashtable

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
    #>
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	Param(
		[Parameter(ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		if (-not [System.String]::IsNullOrEmpty($Session)) {
			if ($script:Sessions.ContainsKey($Session)) {
				Write-Output -InputObject $script:Sessions.Get_Item($Session)
			}
            else {
                Write-Output -InputObject $null
            }
		}
		else {
			Write-Output -InputObject $script:Sessions
		}
	}

	End {
	}
}

Function Remove-CESession {
    <#
        .SYNOPSIS
            Removes stored CE session information

        .DESCRIPTION
            The cmdlet removes CE session information generated by the New-CESession cmdlet.

        .PARAMETER Session
            Specifies the unique identifier of the session to remove. If this parameter is not specified, all stored sessions are removed.

        .EXAMPLE
            Remove-CESession

            Removes all CE session information stored in the script variable.

        .INPUTS
            None or System.String

        .OUTPUTS
            None

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
    #>
    [CmdletBinding()]
	[OutputType()]
    Param(
        [Parameter(ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
		$SessionsToEnd = @()

        if ($Session -eq [System.String]::Empty)
        {
			foreach ($SessionInfo in $script:Sessions.GetEnumerator())
			{
				$SessionsToEnd += $SessionInfo.Key
			}
		}
		else
		{
			$SessionsToEnd += $Session
		}

		foreach ($SessionToEnd in $SessionsToEnd)
		{
			$SessionInfo = $Sessions[$SessionToEnd]

			Write-Verbose -Message "Terminating session for $SessionToEnd."

			$Uri = "$($SessionInfo.Url)/logout"

			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.WebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -WebSession $SessionInfo.WebSession -UseBasicParsing -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}

			$script:Sessions.Remove($SessionToEnd.ToLower())

			if ($StatusCode -ne 204)
			{
				Write-Warning -Message "Problem terminating session for $SessionToEnd`: $StatusCode $Reason - $($Result.Content)"
			}
			else
			{
				Write-Verbose -Message "Successfully removed session $SessionToEnd."
			}
		}
    }

    End {
    }
}

#endregion
	`
#region Blueprints

Function New-CEBlueprint {
	<#
		.SYNOPSIS
			Define the target machine characteristics: machine and disk types, network configuration, etc.

			This cmdlet is only used when migrating from AWS to AWS. It is not used for DR or migrating from outside AWS into AWS.

		.DESCRIPTION
			This cmdlet defines the target machine characteristics: machine and disk types, network configuration, etc. There can be only one blueprint per machine per region. Returns the newly created object.

		.PARAMETER Blueprint
			The blueprint to apply, the hashtable can be defined with the following data (this is presented in JSON, which the hashtable will be converted to):

			If you specify a blueprint document, all other configuration parameters are ignored.

			{
			  "iamRole": "string",
			  "scsiAdapterType": "string",
			  "publicIPAction": "ALLOCATE",
			  "machineName": "string",
			  "cpus": 0,
			  "securityGroupIDs": [
				"string"
			  ],
			  "runAfterLaunch": true,
			  "networkInterface": "string",
			  "mbRam": 0,
			  "instanceType": "string",
			  "subnetIDs": [
				"string"
			  ],
			  "coresPerCpu": 0,
			  "staticIp": "string",
			  "tags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "securityGroupAction": "FROM_POLICY",
			  "privateIPs": [
				"string"
			  ],
			  "tenancy": "SHARED",
			  "computeLocationId": "string",
			  "subnetsHostProject": "string",
			  "logicalLocationId": "string",
			  "networkAdapterType": "string",
			  "byolOnDedicatedInstance": true,
			  "placementGroup": "string",
			  "disks": [
				{
				  "iops": 0,
				  "type": "COPY_ORIGIN",
				  "name": "string"
				}
			  ],
			  "privateIPAction": "CREATE_NEW",
			  "staticIpAction": "EXISTING",
			  "dedicatedHostIdentifier": "string",
			  "useSharedRam": true
			}
	
		.PARAMETER Path
			The path to a file containing the JSON definition of the blueprint.

		.PARAMETER IAMRole
			AWS only. The AWS IAM Role to associate with this blueprint.

		.PARAMETER ScsiAdapterType
			VCENTER Only. The scsi adapter type.

		.PARAMETER PublicIPAction
			Whether to allocate an ephemeral public IP, or not. AS_SUBNET causes CloudEndure to copy this property from the source machine.
	
		.PARAMETER MachineName
			The instance to create this blueprint for.

		.PARAMETER Cpus
			VCENTER Only. Number of CPUs per target machine.

		.PARAMETER SecurityGroupIds
			AWS Only. The security groups that will be associated with the instance.

		.PARAMETER RunAfterLaunch
			AWS Only. Specify true to have the instance started after it is launched or false to leave it in a stopped state.

		.PARAMETER NetworkInterface
			VCENTER Only. The network interface to use.

		.PARAMETER MBRAM
			VCENTER Only. The network interface to use.

		.PARAMETER InstanceType
			The instance type to launch the replica as.

		.PARAMETER SubnetIDs
			Specify the subnet Id(s) the instance will be associated with.

		.PARAMETER CoresPerCpu
			VCENTER Only. The number of cores per CPU.

		.PARAMETER StaticIP
			If you select ALLOCATE for StaticIPAction, then specify Elatic IP address to associate with the instance.

		.PARAMETER Tags
			AWS only. Tags that will be applied to the target machine. This parameter must specify Key and Value. For example:

			@(@{Key = "name"; Value = "my server"}, @{Key = "env"; Value = "dev"})

		.PARAMETER SecurityGroupAction
			Currently only supports the value "FROM_POLICY".

		.PARAMETER PrivateIPs
			If you select CUSTOM for PrivateIPAction, specify the private IPs you want associated with the instance.

		.PARAMETER Tenancy
			The tenancy of the replica.

		.PARAMETER ComputeLocationId
			VCENTER only.

		.PARAMETER SubnetsHostProject
			GCP only. Host project for cross project network subnet.

		.PARAMETER LogicalLocationId
			VCENTER only. vcenter = vmFolder; relates to $ref LogicalLocation

		.PARAMETER NetworkAdapterType
			VCENTER only. The type of network adapter to use.

		.PARAMETER BYOLOnDedicatedInstance
			AWS only. Specifies whether to use byol windows license if dedicated instance tenancy is selected.

		.PARAMETER PlacementGroup
			AWS Only. The placement group to launch the instance in.

		.PARAMETER Disks
			AWS only. Target machine disk properties. An array of objects with properties as follows:

				IOPS: Int >= 0
				TYPE: "COPY_ORIGIN", "STANDARD", "SSD", "PROVISIONED_SSD", "ST1", "SC1"
				NAME: Disk name as appears in the source machine object.

		.PARAMETER PrivateIPAction
			The action for the instance's private IP address.

		.PARAMETER StaticIpAction
			The action for the instance's static IP address.

		.PARAMETER DedicatedHostIdentifier
			AWS only. The Id for the dedicated host.

		.PARAMETER UseSharedRAM
			VCENTER only. Specifies whether to use shared RAM for the replica.		

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			Passes through the created object.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.EXAMPLE
			New-CEBlueprint -MachineName "MyTestMachine" -IAMRole EC2StandardInstanceProfile -SubnetIDs @("subnet-152acf5d") -SecurityGroupIDs ("sg-6053bf1f") 

			Creates a new blueprint and associates an AWS IAM Role, a specific deployment subnet, and a security group belonging to the VPC containing the subnet.

		.EXAMPLE
			New-CEBlueprint -MachineName "MyTestMachine" -SubnetIDs @("Default")
			
			Deploys the machine into the default subnet for configured target region.

		.INPUTS
            None or System.Collections.Hashtable

        .OUTPUTS
           None or System.Management.Automation.PSCustomObject

			The JSON representation of the return value:

			{
			  "iamRole": "string",
			  "scsiAdapterType": "string",
			  "publicIPAction": "ALLOCATE",
			  "machineName": "string",
			  "cpus": 0,
			  "securityGroupIDs": [
				"string"
			  ],
			  "runAfterLaunch": true,
			  "recommendedPrivateIP": "string",
			  "networkInterface": "string",
			  "id": "string",
			  "mbRam": 0,
			  "instanceType": "string",
			  "subnetIDs": [
				"string"
			  ],
			  "coresPerCpu": 0,
			  "recommendedInstanceType": "string",
			  "staticIp": "string",
			  "tags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "securityGroupAction": "FROM_POLICY",
			  "privateIPs": [
				"string"
			  ],
			  "tenancy": "SHARED",
			  "computeLocationId": "string",
			  "subnetsHostProject": "string",
			  "logicalLocationId": "string",
			  "networkAdapterType": "string",
			  "byolOnDedicatedInstance": true,
			  "placementGroup": "string",
			  "machineId": "string",
			  "region": "string",
			  "disks": [
				{
				  "iops": 0,
				  "type": "COPY_ORIGIN",
				  "name": "string"
				}
			  ],
			  "privateIPAction": "CREATE_NEW",
			  "staticIpAction": "EXISTING",
			  "dedicatedHostIdentifier": "string",
			  "useSharedRam": true
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/16/2019
			
	#>
	[CmdletBinding(DefaultParameterSetName="__AllParameterSets")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0, ParameterSetName = "Blueprint")]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$Blueprint = @{},

		[Parameter(Mandatory = $true, ParameterSetName = "BlueprintFile")]
		[ValidateScript({
			Test-Path $_
		})]
		[System.String]$Path,

		[Parameter()]
		[ValidateSet("ALLOCATE", "DONT_ALLOCATE", "AS_SUBENT")]
		[System.String]$PublicIPAction,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$MachineName,

		[Parameter(ParameterSetName = "AWS")]
		[System.Boolean]$RunAfterLaunch = $true,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$NetworkInterface,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateRange(0, 32)]
		[System.Int32]$CoresPerCpu,		

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$Tags = @(),

		[Parameter()]
		[ValidateSet("FROM_POLICY")]
		[System.String]$SecurityGroupAction = "FROM_POLICY",

		[Parameter()]
		[ValidateSet("SHARED", "DEDICATED", "HOST")]
		[System.String]$Tenancy,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$ComputeLocationId,

		[Parameter(ParameterSetName = "GCP")]
		[ValidateNotNullOrEmpty()]
		[System.String]$SubnetsHostProject,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$LogicalLocationId,

		[Parameter(ParameterSetName = "AWS")]
		[System.Boolean]$BYOLOnDedicatedInstance,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$Disks,

		[Parameter()]
		[ValidateSet("CREATE_NEW", "COPY_ORIGIN", "CUSTOM_IP")]
		[System.String]$PrivateIPAction,

		[Parameter()]
		[ValidateSet("EXISTING", "DONT_CREATE", "CREATE_NEW", "IF_IN_ORIGIN")]
		[System.String]$StaticIPAction,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNullOrEmpty()]
		[System.String]$DedicatedHostIdentifier,

		[Parameter(ParameterSetName = "VCENTER")]
		[System.Boolean]$UseSharedRam,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	DynamicParam {

		# Create the dictionary 
        [System.Management.Automation.RuntimeDefinedParameterDictionary]$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		# Only generate the dynamic parameters if a blueprint doc wasn't specified
		if (-not $PSBoundParameters.ContainsKey("Blueprint") -and -not $PSBoundParameters.ContainsKey("Path"))
		{
			$DynSplat = @{}

			if (-not [System.String]::IsNullOrEmpty($Session)) {
				$DynSplat.Add("Session", $Session)
			}

			if ($ProjectId -ne $null -and $ProjectId -ne [System.Guid]::Empty)
			{
				$DynSplat.Add("ProjectId", $ProjectId)
			}

			[PSCustomObject]$TargetCloudRegion = Get-CETargetCloudRegion @DynSplat

			$InstanceTypes = $TargetCloudRegion.InstanceTypes
			$InstanceTypes += "COPY_ORIGIN"
			$InstanceTypes += "CUSTOM"

			New-DynamicParameter -Name "InstanceType" -Type ([System.String]) -ValidateSet $InstanceTypes -Mandatory -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

			if ($PrivateIPAction -ieq "CUSTOM_IP")
			{
				New-DynamicParameter -Name "PrivateIPs" -Type ([System.String[]]) -ValidateNotNullOrEmpty -Mandatory -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			}

			if ($StaticIPAction -ieq "EXISTING")
			{
				New-DynamicParameter -Name "StaticIP" -Type ([System.String]) -Mandatory -ValidateSet $TargetCloudRegion.StaticIPs -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			}

			if ($TargetCloudRegion -ne "GENERIC")
			{
				$CloudName = Get-CECloud -Id $TargetCloudRegion.Cloud | Select-Object -ExpandProperty Name
			}
			else
			{
				$CloudName = $TargetCloudRegion
			}
			
			switch ($CloudName)
			{
				"AWS" {

					if ($TargetCloudRegion.IAMRoles.Length -gt 0)
					{
						New-DynamicParameter -Name "IAMRole" -Type ([System.String]) -ParameterSets @("AWS") -ValidateSet $TargetCloudRegion.IAMRoles -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					if ($TargetCloudRegion.PlacementGroups.Length -gt 0)
					{
						New-DynamicParameter -Name "PlacementGroup" -Type ([System.String]) -ValidateSet ($TargetCloudRegion.PlacementGroups) -ParameterSets @("AWS") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					if ($TargetCloudRegion.Subnets.Length -gt 0)
					{
						$SubnetSet = $TargetCloudRegion.Subnets | Where-Object {$_.SubnetId -ne $null } | Select-Object -ExpandProperty SubnetId
						# Add default to allow user to specify the default subnet for the configured region
						$SubnetSet += "Default"

						New-DynamicParameter -Name "SubnetIDs" -Type ([System.String[]]) -ValidateSet $SubnetSet -ParameterSets @("AWS") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					$Type = Import-UnboundParameterCode -PassThru
					$Subnets = $Type.GetMethod("GetUnboundParameterValue").MakeGenericMethod([System.Object]).Invoke($Type, @($PSCmdlet, "SubnetIDs", -1))

					# Get the first subnet Id
					$Key = [System.String]::Empty

					if ($Subnets -is [System.Array])
					{
						$Key = $Subnets[0]
					}
					elseif ($Subnets -is [System.String])
					{
						if (-not [System.String]::IsNullOrEmpty($Subnets))
						{
							$Key = $Subnets
						}
					}

					# Attempt to get the first subnet from the target region object
					$Subnet = $TargetCloudRegion.Subnets | Where-Object {$_.Name -ieq $Key -or $_.SubnetId -ieq $Key} | Select-Object -First 1 -ErrorAction SilentlyContinue

					# If the subnet is "Default", you won't be able to select a security group, so a new one will be created
					# Make sure there are security groups in this region and that we found a matching one
					# Subnet will be null if user selected "Default"
					if ($TargetCloudRegion.SecurityGroups -ne $null -and $TargetCloudRegion.SecurityGroups.Length -gt 0 -and $Subnet -ne $null)
					{
						# Get the network Id based on the selected subnet so we can get the right security groups as options
						[System.String[]]$SGSet = $TargetCloudRegion.SecurityGroups | Where-Object {$_.NetworkId -ieq $Subnet.NetworkId} | Select-Object -ExpandProperty SecurityGroupId

						New-DynamicParameter -Name "SecurityGroupIDs" -Type ([System.String[]]) -ParameterSets @("AWS") -ValidateSet $SGSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					break
				}
				"GCP" {

					break
				}
				"Azure" {

					break
				}
				"VCENTER" {
					if ($TargetCloudRegion.scsiAdapterTypes.Length -gt 0)
					{
						New-DynamicParameter -Name "SCSIAdapterType" -Type ([System.String]) -ParameterSets @("VCENTER") -ValidateSet $TargetCloudRegion.scsiAdapterTypes -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					New-DynamicParameter -Name "Cpus" -Type ([System.Int32]) -ParameterSets @("VCENTER") -ValidateRange @(1, $TargetCloudRegion.maxCoresPerMachineCpu) -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

					if ($TargetCloudRegion.networkAdapterTypes.Length -gt 0)
					{
						New-DynamicParameter -Name "NetworkAdapterType" -Type ([System.String]) -ParameterSets @("VCENTER") -ValidateSet $TargetCloudRegion.networkAdapterTypes -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					New-DynamicParameter -Name "CoresPerCpu" -Type ([System.Int32]) -ParameterSets @("VCENTER") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					
					New-DynamicParameter -Name "MBRAM" -Type ([System.Int32]) -ParameterSets @("VCENTER") -ValidateSet $TargetCloudRegion.maxCoresPerMachineCpu -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					
					break
				}
				"GENERIC" {

					break
				}
				default {
					throw "The cloud environment $CloudName is not supported by this cmdlet yet."
					break
				}
			}
		}

		return $RuntimeParameterDictionary
	}

	Begin {
	}

	Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		$Body = ""
		$BlueprintObject = [PSCustomObject]@{}
		switch ($PSCmdlet.ParameterSetName)
		{
			"BlueprintFile" {
				$BlueprintObject = Get-Content -Path $Path -Raw | Convert-FromJson
				break
			}
			"Blueprint" {
				$BlueprintObject = [PSCustomObject]$Blueprint
				break
			}
			default {
				# This is going to take all of the parameters supplied, put them into a hash table, and then create a json
				# document that is the blueprint
				$Blueprint = Convert-ParametersToHashtable -Parameters (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters `
					-ParameterSetName $PSCmdlet.ParameterSetName `
					-RuntimeParameterDictionary $RuntimeParameterDictionary `
					-BoundParameters $PSBoundParameters 

				if ($BluePrint["StaticIPAction"] -ne "EXISTING") {
					$BluePrint["staticIP"] = ""
				}

				if ($BluePrint["PrivateIPAction"] -ne "CUSTOM_IP") {
					$BluePrint["privateIPs"] = @()
				}

				$BlueprintObject = [PSCustomObject]$Blueprint
			}
		}

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$UrlPath = "/projects/$ProjectId/blueprints"
		$Body = ConvertTo-Json -InputObject $Blueprint

		Write-Verbose -Message "Creating new blueprint:`r`n$Body"

		try {
			$Result = Invoke-CERequest -Path $UrlPath -Body $Body -Method Post -Session $Session -ExpectedResponseCode 201
			Write-Verbose -Message "Blueprint successfully created."

			if ($PassThru)
			{
				Write-Output -InputObject $Result
			}
		}
		catch [Exception] {
			throw "There was an issue creating the new blueprint: $($_.Exception.Message)"
		}	
	}

	End {
	}
}

Function Get-CEBlueprint {
	<#
        .SYNOPSIS
			Gets blueprint information.

        .DESCRIPTION
			The cmdlet retrieves a specific blueprint or a lost of blueprints of the specified or default project if no Id is provided.

		.PARAMETER Id
			The blueprint Id to retrieve. If this parameter is not specified, the blueprints are listed.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER All
			Gets all blueprints without paging the results.
            
        .EXAMPLE
            Get-CEBlueprint

            Retrieves the blueprints (up to 1500 starting at index 0) of the default project.

		.EXAMPLE
            Get-CEBlueprint -Offset 1501 -Limit 10

            Retrieves the blueprints at index 1501 through 1511. This skips listing the first 1501 blueprints (offset is a 0 based index).

		.EXAMPLE 
			Get-CEBlueprint -Id 184142f8-a581-4c86-9285-e24382d60d55

			Gets the blueprint matching the provided Id.

        .INPUTS
            None or System.Guid

        .OUTPUTS
           System.Management.Automation.PSCustomObject[] or System.Management.Automation.PSCustomObject

			The JSON representation of the array:

			[
				{
				  "iamRole": "string",
				  "scsiAdapterType": "string",
				  "publicIPAction": "ALLOCATE",
				  "machineName": "string",
				  "cpus": 0,
				  "securityGroupIDs": [
					"string"
				  ],
				  "runAfterLaunch": true,
				  "recommendedPrivateIP": "string",
				  "networkInterface": "string",
				  "id": "string",
				  "mbRam": 0,
				  "instanceType": "string",
				  "subnetIDs": [
					"string"
				  ],
				  "coresPerCpu": 0,
				  "recommendedInstanceType": "string",
				  "staticIp": "string",
				  "tags": [
					{
					  "key": "string",
					  "value": "string"
					}
				  ],
				  "securityGroupAction": "FROM_POLICY",
				  "privateIPs": [
					"string"
				  ],
				  "tenancy": "SHARED",
				  "computeLocationId": "string",
				  "subnetsHostProject": "string",
				  "logicalLocationId": "string",
				  "networkAdapterType": "string",
				  "byolOnDedicatedInstance": true,
				  "placementGroup": "string",
				  "machineId": "string",
				  "region": "string",
				  "disks": [
					{
					  "iops": 0,
					  "type": "COPY_ORIGIN",
					  "name": "string"
					}
				  ],
				  "privateIPAction": "CREATE_NEW",
				  "staticIpAction": "EXISTING",
				  "dedicatedHostIdentifier": "string",
				  "useSharedRam": true
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/17/2019
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    Param(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0, ParameterSetName = "Get")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter(ParameterSetName = "All")]
		[Switch]$All,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session
		
		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$Path = "/projects/$ProjectId/blueprints"

		[PSCustomObject[]]$Results = @()

		switch ($PSCmdlet.ParameterSetName)
		{
			"Get" {
				if ($Id -ne [System.Guid]::Empty)
				{
					$Path += "/$($Id.ToString())"
				}

				$ErrorHandling = {
					Param($StatusCode, $Content, $ErrorMessage, $BlueprintId)
				
					switch ($StatusCode)
					{
						200 {
							Write-Output -InputObject $Content
							break
						}
						404 {
							throw "Could not find a blueprint with id $BlueprintId."
						}
						default {
							throw $ErrorMessage
						}			
					}
				}

				try {
					$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ErrorHandling $ErrorHandling -ErrorHandlingArgs @($Id)
				}
				catch [Exception] {
					throw "There was an issue retrieving blueprints: $($_.Exception.Message)."
				}

				$Results += $Result

				break
			}
			"List" {

				# If non default values for either were specified, update the URI
				if ($Offset -gt 0 -or $Limit -lt 1500)
				{
					$QueryString = [System.String]::Empty

					if ($Offset -gt 0)
					{
						$QueryString += "&offset=$Offset"
					}

					if ($Limit -lt 1500)
					{
						$QueryString += "&limit=$Limit"
					}

					# Remove the first character which is an unecessary ampersand
					$Path += "?$($QueryString.Substring(1))"
				}

				try {
					$Result = Invoke-CERequest -Method Get -Path $Path -Session $Session -ExpectedResponseCode 200
					$Results += $Result
				}
				catch [Exception] {
					throw "There was an issue retrieving blueprints: $($_.Exception.Message)"
				}
				
				break
			}
			"All" {

				$Offset = 0
				$Limit = 1500
				[System.Int32]$ResultCount = 0

				# Go until the results returned are less than the specified limit
				do
				{
					Write-Verbose -Message "Querying blueprints from $Offset to $($Offset + $Limit)."

					[System.String]$QueryString = "?offset=$Offset&limit=$Limit"
					[System.String]$TempUri = "$Path$QueryString"
					
					try {
						$Result = Invoke-CERequest -Method Get -Path $TempUri -Session $Session -ExpectedResponseCode 200
						$Results += $Result
						$ResultCount = $Result.Length
						$Offset += $Limit
					}
					catch [Exception] {
						throw "There was an issue retrieving blueprints: $($_.Exception.Message)"
					}
				} while ($ResultCount -ge $Limit)

				break
			}
			default {
				throw "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
				break
			}
		}

		if ($PSCmdlet.ParameterSetName -eq "Get")
		{
			Write-Output -InputObject $Results[0]
		}
		else
		{
			# In case this is a 1 item array, don't unbox
			,$Results
		}
    }

    End {
    }
}

Function Set-CEBlueprint {
	<#
        .SYNOPSIS
			Sets a blueprint for a CE Instance.

        .DESCRIPTION
			The cmdlet updates the blueprint for a specific CE Instance. Set a parameter to an empty string to clear it from the blueprint.

			Currently, this cmdlet only supports AWS target cloud environments.

		.PARAMETER Blueprint
			The updated blueprint data to send. This hashtable only needs to contain the data that you want to update. The original blueprint will be merged with this one.

			If you specify a blueprint, all other configuration parameters are ignored.

			The available configuration items are:

			{
			  "iamRole": "string",
			  "scsiAdapterType": "string",
			  "publicIPAction": "ALLOCATE",
			  "machineName": "string",
			  "cpus": 0,
			  "securityGroupIDs": [
				"string"
			  ],
			  "runAfterLaunch": true,
			  "networkInterface": "string",
			  "mbRam": 0,
			  "instanceType": "string",
			  "subnetIDs": [
				"string"
			  ],
			  "coresPerCpu": 0,
			  "staticIp": "string",
			  "tags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "securityGroupAction": "FROM_POLICY",
			  "privateIPs": [
				"string"
			  ],
			  "tenancy": "SHARED",
			  "computeLocationId": "string",
			  "subnetsHostProject": "string",
			  "logicalLocationId": "string",
			  "networkAdapterType": "string",
			  "byolOnDedicatedInstance": true,
			  "placementGroup": "string",
			  "disks": [
				{
				  "iops": 0,
				  "type": "COPY_ORIGIN",
				  "name": "string"
				}
			  ],
			  "privateIPAction": "CREATE_NEW",
			  "staticIpAction": "EXISTING",
			  "dedicatedHostIdentifier": "string",
			  "useSharedRam": true
			}

		.PARAMETER Path
			The path to a file containing the JSON definition of the blueprint.

		.PARAMETER IAMRole
			AWS only. The AWS IAM Role to associate with this blueprint.

		.PARAMETER ScsiAdapterType
			VCENTER Only. The scsi adapter type.

		.PARAMETER PublicIPAction
			Whether to allocate an ephemeral public IP, or not. AS_SUBNET causes CloudEndure to copy this property from the source machine.
	
		.PARAMETER MachineName
			The instance to create this blueprint for.

		.PARAMETER Cpus
			VCENTER Only. Number of CPUs per target machine.

		.PARAMETER SecurityGroupIds
			AWS Only. The security groups that will be associated with the instance.

		.PARAMETER RunAfterLaunch
			AWS Only. Specify true to have the instance started after it is launched or false to leave it in a stopped state.

		.PARAMETER NetworkInterface
			VCENTER Only. The network interface to use.

		.PARAMETER MBRAM
			VCENTER Only. The network interface to use.

		.PARAMETER InstanceType
			The instance type to launch the replica as.

		.PARAMETER SubnetIDs
			Specify the subnet Id(s) the instance will be associated with.

		.PARAMETER CoresPerCpu
			VCENTER Only. The number of cores per CPU.

		.PARAMETER StaticIP
			If you select ALLOCATE for StaticIPAction, then specify Elatic IP address to associate with the instance.

		.PARAMETER Tags
			AWS only. Tags that will be applied to the target machine. This parameter must specify Key and Value. For example:

			@(@{Key = "name"; Value = "my server"}, @{Key = "env"; Value = "dev"})

		.PARAMETER SecurityGroupAction
			Currently only supports the value "FROM_POLICY".

		.PARAMETER PrivateIPs
			If you select CUSTOM for PrivateIPAction, specify the private IPs you want associated with the instance.

		.PARAMETER Tenancy
			The tenancy of the replica.

		.PARAMETER ComputeLocationId
			VCENTER only.

		.PARAMETER SubnetsHostProject
			GCP only. Host project for cross project network subnet.

		.PARAMETER LogicalLocationId
			VCENTER only. vcenter = vmFolder; relates to $ref LogicalLocation

		.PARAMETER NetworkAdapterType
			VCENTER only. The type of network adapter to use.

		.PARAMETER BYOLOnDedicatedInstance
			AWS only. Specifies whether to use byol windows license if dedicated instance tenancy is selected.

		.PARAMETER PlacementGroup
			AWS Only. The placement group to launch the instance in.

		.PARAMETER Disks
			AWS only. Target machine disk properties. An array of objects with properties as follows:

				IOPS: Int >= 0
				TYPE: "COPY_ORIGIN", "STANDARD", "SSD", "PROVISIONED_SSD", "ST1", "SC1"
				NAME: Disk name as appears in the source machine object.

		.PARAMETER PrivateIPAction
			The action for the instance's private IP address.

		.PARAMETER StaticIpAction
			The action for the instance's static IP address.

		.PARAMETER DedicatedHostIdentifier
			AWS only. The Id for the dedicated host.

		.PARAMETER UseSharedRAM
			VCENTER only. Specifies whether to use shared RAM for the replica.		

		.PARAMETER InstanceId
			The id of the CE instance whose blueprint you want to update.

		.PARAMETER BlueprintId
			The id of the CE blueprint you want to update.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			The updated blueprint will be returned to the pipeline.

        .EXAMPLE
            Set-CEBlueprint -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708 -Blueprint @{"IAMRole" = "EC2-InstanceProfile-Public"}

			This adds or updates the IAMRole property for the blueprint to "EC2-InstanceProfile-Public" for the CE instance identified by 47d842b8-ebfa-4695-90f8-fb9ab686c708.

		.EXAMPLE
			Set-CEBlueprint -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708 -IAMRole "EC2-InstanceProfile-Public"

			This adds or updates the IAMRole property for the blueprint to "EC2-InstanceProfile-Public" for the CE instance identified by 47d842b8-ebfa-4695-90f8-fb9ab686c708.

        .INPUTS
            None or System.Collections.Hashtable

        .OUTPUTS
           None or System.Management.Automation.PSCustomObject

			The JSON representation of the return value:
			{
			  "iamRole": "string",
			  "scsiAdapterType": "string",
			  "publicIPAction": "ALLOCATE",
			  "machineName": "string",
			  "cpus": 0,
			  "securityGroupIDs": [
				"string"
			  ],
			  "runAfterLaunch": true,
			  "networkInterface": "string",
			  "mbRam": 0,
			  "instanceType": "string",
			  "subnetIDs": [
				"string"
			  ],
			  "coresPerCpu": 0,
			  "staticIp": "string",
			  "tags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "securityGroupAction": "FROM_POLICY",
			  "privateIPs": [
				"string"
			  ],
			  "tenancy": "SHARED",
			  "computeLocationId": "string",
			  "subnetsHostProject": "string",
			  "logicalLocationId": "string",
			  "networkAdapterType": "string",
			  "byolOnDedicatedInstance": true,
			  "placementGroup": "string",
			  "disks": [
				{
				  "iops": 0,
				  "type": "COPY_ORIGIN",
				  "name": "string"
				}
			  ],
			  "privateIPAction": "CREATE_NEW",
			  "staticIpAction": "EXISTING",
			  "dedicatedHostIdentifier": "string",
			  "useSharedRam": true
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/17/2019
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
    [OutputType([PSCustomObject])]
    Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Instance")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid]$InstanceId = [System.Guid]::Empty,

		[Parameter(Mandatory = $true, ParameterSetName = "Id")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid]$BlueprintId = [System.Guid]::Empty,

		[Parameter(Mandatory = $true, ParameterSetName = "Blueprint", ValueFromPipeline = $true, Position = 0)]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$Blueprint = @{},

		[Parameter(Mandatory = $true, ParameterSetName = "BlueprintFile")]
		[ValidateScript({
			Test-Path $_
		})]
		[System.String]$Path,

		[Parameter()]
		[ValidateSet("ALLOCATE", "DONT_ALLOCATE", "AS_SUBENT")]
		[System.String]$PublicIPAction,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$MachineName,

		[Parameter(ParameterSetName = "AWS")]
		[System.Boolean]$RunAfterLaunch = $true,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$NetworkInterface,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateRange(0, 32)]
		[System.Int32]$CoresPerCpu,		

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$Tags = @(),

		[Parameter()]
		[ValidateSet("FROM_POLICY")]
		[System.String]$SecurityGroupAction = "FROM_POLICY",

		[Parameter()]
		[ValidateSet("SHARED", "DEDICATED", "HOST")]
		[System.String]$Tenancy,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$ComputeLocationId,

		[Parameter(ParameterSetName = "GCP")]
		[ValidateNotNullOrEmpty()]
		[System.String]$SubnetsHostProject,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$LogicalLocationId,

		[Parameter(ParameterSetName = "AWS")]
		[System.Boolean]$BYOLOnDedicatedInstance,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$Disks,

		[Parameter()]
		[ValidateSet("CREATE_NEW", "COPY_ORIGIN", "CUSTOM_IP")]
		[System.String]$PrivateIPAction,

		[Parameter()]
		[ValidateSet("EXISTING", "DONT_CREATE", "CREATE_NEW", "IF_IN_ORIGIN")]
		[System.String]$StaticIPAction,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNullOrEmpty()]
		[System.String]$DedicatedHostIdentifier,

		[Parameter(ParameterSetName = "VCENTER")]
		[System.Boolean]$UseSharedRam,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force
    )

	DynamicParam {

		# Create the dictionary 
        [System.Management.Automation.RuntimeDefinedParameterDictionary]$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		# Only generate the dynamic parameters if a blueprint doc wasn't specified
		if (-not $PSBoundParameters.ContainsKey("Blueprint") -and -not $PSBoundParameters.ContainsKey("Path"))
		{
			$DynSplat = @{}

			if (-not [System.String]::IsNullOrEmpty($Session)) {
				$DynSplat.Add("Session", $Session)
			}

			if ($ProjectId -ne $null -and $ProjectId -ne [System.Guid]::Empty)
			{
				$DynSplat.Add("ProjectId", $ProjectId)
			}

			[PSCustomObject]$TargetCloudRegion = Get-CETargetCloudRegion @DynSplat

			$InstanceTypes = $TargetCloudRegion.InstanceTypes
			$InstanceTypes += "COPY_ORIGIN"
			$InstanceTypes += "CUSTOM"

			New-DynamicParameter -Name "InstanceType" -Type ([System.String]) -ValidateSet $InstanceTypes -Mandatory -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

			if ($PrivateIPAction -ieq "CUSTOM_IP")
			{
				New-DynamicParameter -Name "PrivateIPs" -Type ([System.String[]]) -ValidateNotNullOrEmpty -Mandatory -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			}

			if ($StaticIPAction -ieq "EXISTING")
			{
				New-DynamicParameter -Name "StaticIP" -Type ([System.String]) -Mandatory -ValidateSet $TargetCloudRegion.StaticIPs -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			}

			if ($TargetCloudRegion -ne "GENERIC")
			{
				$CloudName = Get-CECloud -Id $TargetCloudRegion.Cloud | Select-Object -ExpandProperty Name
			}
			else
			{
				$CloudName = $TargetCloudRegion
			}
			
			switch ($CloudName)
			{
				"AWS" {

					if ($TargetCloudRegion.IAMRoles.Length -gt 0)
					{
						New-DynamicParameter -Name "IAMRole" -Type ([System.String]) -ParameterSets @("AWS") -ValidateSet $TargetCloudRegion.IAMRoles -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					if ($TargetCloudRegion.PlacementGroups.Length -gt 0)
					{
						New-DynamicParameter -Name "PlacementGroup" -Type ([System.String]) -ValidateSet ($TargetCloudRegion.PlacementGroups) -ParameterSets @("AWS") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					if ($TargetCloudRegion.Subnets.Length -gt 0)
					{
						$SubnetSet = $TargetCloudRegion.Subnets | Where-Object {$_.SubnetId -ne $null } | Select-Object -ExpandProperty SubnetId
						# Add default to allow user to specify the default subnet for the configured region
						$SubnetSet += "Default"

						New-DynamicParameter -Name "SubnetIDs" -Type ([System.String[]]) -ValidateSet $SubnetSet -ParameterSets @("AWS") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					$Type = Import-UnboundParameterCode -PassThru
					$Subnets = $Type.GetMethod("GetUnboundParameterValue").MakeGenericMethod([System.Object]).Invoke($Type, @($PSCmdlet, "SubnetIDs", -1))

					# Get the first subnet Id
					$Key = [System.String]::Empty

					if ($Subnets -is [System.Array])
					{
						$Key = $Subnets[0]
					}
					elseif ($Subnets -is [System.String])
					{
						if (-not [System.String]::IsNullOrEmpty($Subnets))
						{
							$Key = $Subnets
						}
					}

					# Attempt to get the first subnet from the target region object
					$Subnet = $TargetCloudRegion.Subnets | Where-Object {$_.Name -ieq $Key -or $_.SubnetId -ieq $Key} | Select-Object -First 1 -ErrorAction SilentlyContinue

					# If the subnet is "Default", you won't be able to select a security group, so a new one will be created
					# Make sure there are security groups in this region and that we found a matching one
					# Subnet will be null if user selected "Default"
					if ($TargetCloudRegion.SecurityGroups -ne $null -and $TargetCloudRegion.SecurityGroups.Length -gt 0 -and $Subnet -ne $null)
					{
						# Get the network Id based on the selected subnet so we can get the right security groups as options
						[System.String[]]$SGSet = $TargetCloudRegion.SecurityGroups | Where-Object {$_.NetworkId -ieq $Subnet.NetworkId} | Select-Object -ExpandProperty SecurityGroupId

						New-DynamicParameter -Name "SecurityGroupIDs" -Type ([System.String[]]) -ParameterSets @("AWS") -ValidateSet $SGSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					break
				}
				"GCP" {

					break
				}
				"Azure" {

					break
				}
				"VCENTER" {
					if ($TargetCloudRegion.scsiAdapterTypes.Length -gt 0)
					{
						New-DynamicParameter -Name "SCSIAdapterType" -Type ([System.String]) -ParameterSets @("VCENTER") -ValidateSet $TargetCloudRegion.scsiAdapterTypes -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					New-DynamicParameter -Name "Cpus" -Type ([System.Int32]) -ParameterSets @("VCENTER") -ValidateRange @(1, $TargetCloudRegion.maxCoresPerMachineCpu) -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

					if ($TargetCloudRegion.networkAdapterTypes.Length -gt 0)
					{
						New-DynamicParameter -Name "NetworkAdapterType" -Type ([System.String]) -ParameterSets @("VCENTER") -ValidateSet $TargetCloudRegion.networkAdapterTypes -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					New-DynamicParameter -Name "CoresPerCpu" -Type ([System.Int32]) -ParameterSets @("VCENTER") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					
					New-DynamicParameter -Name "MBRAM" -Type ([System.Int32]) -ParameterSets @("VCENTER") -ValidateSet $TargetCloudRegion.maxCoresPerMachineCpu -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					
					break
				}
				"GENERIC" {

					break
				}
				default {
					throw "The cloud environment $CloudName is not supported by this cmdlet yet."
					break
				}
			}
		}

		return $RuntimeParameterDictionary
	}

    Begin {      
    }

    Process {
        $SessionInfo = Get-CESessionOrDefault -Session $Session

		$DynSplat = @{}

		if ([System.String]::IsNullOrEmpty($Session))
		{
			$DynSplat.Add("Session", $Session)
		}

		if ($BlueprintId -ne [System.Guid]::Empty)
		{
			# This will throw an exception if the blueprint can't be found
			[System.Collections.Hashtable]$ExistingBlueprint = Get-CEBlueprint -Id $BlueprintId @DynSplat | ConvertTo-Hashtable
		}
		else
		{
			[System.Collections.Hashtable]$ExistingBlueprint = Get-CEBlueprint -All @DynSplat | Where-Object {$_.machineId -eq $InstanceId} | Select-Object -First 1 | ConvertTo-Hashtable

			if ($ExistingBlueprint -eq $null)
			{
				throw "Could not find an existing blueprint for instance $InstanceId."
			}
		}

		$BlueprintObject = [PSCustomObject]@{}

		switch ($PSCmdlet.ParameterSetName)
		{
			"BlueprintFile" {
				$BlueprintObject = Get-Content -Path $Path -Raw | Convert-FromJson
				break
			}
			"Blueprint" {
				$BlueprintObject = [PSCustomObject]$Blueprint
				break
			}
			default {
				# This is going to take all of the parameters supplied, put them into a hash table, and then create a json
				# document that is the blueprint
				$Blueprint = Convert-ParametersToHashtable -Parameters (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters `
					-ParameterSetName $PSCmdlet.ParameterSetName `
					-RuntimeParameterDictionary $RuntimeParameterDictionary `
					-BoundParameters $PSBoundParameters 

				$BlueprintObject = [PSCustomObject]$Blueprint
			}
		}

		# Merge the original and new blueprint
		[System.Collections.Hashtable]$NewBluePrint = Merge-HashTables -Source $ExistingBlueprint -Update ($BlueprintObject | ConvertTo-Hashtable)

        if ($NewBluePrint["StaticIPAction"] -ne "EXISTING") {
            $NewBluePrint["StaticIP"] = ""
        }

        if ($NewBluePrint["PrivateIPAction"] -ne "CUSTOM_IP") {
            $NewBluePrint["PrivateIPs"] = @()
        }

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$UrlPath = "/projects/$ProjectId/blueprints/$($NewBluePrint["Id"])"

		$ConfirmMessage = "Are you sure you want to update the blueprint configuration?"

		$Body = ConvertTo-Json -InputObject $NewBluePrint

		$WhatIfDescription = "Updated blueprint to $Body"
		$ConfirmCaption = "Update Blueprint"

		if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
		{
			Write-Verbose -Message "Updating blueprint to :`r`n$Body"
			
			try {
				$Result = Invoke-CERequest -Path $UrlPath -Body $Body -Method Patch -Session $Session

				Write-Verbose -Message "Blueprint successfully modified."

				if ($PassThru)
				{
					Write-Output -InputObject $Result
				}
			}
			catch [Exception] {
				throw "There was an issue updating the blueprint: $($_.Exception.Message)"
			}
		}
    }

    End {
    }
}

#endregion

#region Replication Configuration

Function Get-CEMachineRecoveryPoints {
	<#
		.SYNOPSIS
			Returns the list of available recovery points for the specified machine.

		.DESCRIPTION
			Returns the list of available recovery points for the specified machine.

			This is only available if the license type is DR.

		.PARAMETER InstanceId
			The CE instance to retrieve recovery points in time information about.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

        .EXAMPLE
			Get-CEMachineRecoveryPoints -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708

			This gets a list of the recovery points for the specified instance.

		.EXAMPLE
			Get-CEMachineRecoveryPoints -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708 -Offset 1501 -Limit 50

			This gets a list of the recovery points for the specified instance from index 1501 to 1551.

        .INPUTS
            System.Guid

        .OUTPUTS
           System.Management.Automation.PSCustomObject[]
			
			The JSON representation of the array:
			[
				{
					"id": "string",
					"dateTime": "2017-09-06T01:39:46Z"
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$InstanceId,

		[Parameter()]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter()]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {

		$SessionInfo = Get-CESessionOrDefault -Session $Session
		
		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$Path = "/projects/$ProjectId/machines/$InstanceId/pointsintime"

		if ($Offset -gt 0 -or $Limit -lt 1500)
		{
			$QueryString = [System.String]::Empty

			if ($Offset -gt 0)
			{
				$QueryString += "&offset=$Offset"
			}

			if ($Limit -lt 1500)
			{
				$QueryString += "&limit=$Limit"
			}

			# Remove the first character which is an unecessary ampersand
			$Path += "?$($QueryString.Substring(1))"
		}

		try {
			$Resuult = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
			Write-Output -InputObject $Result.Items
		}
		catch [Exception] {
			throw "There was an issue retrieving the recovery points: $($_.Exception.Message)"
		}			
	}

	End {
	}
}

Function Get-CEMachineBandwidth {
	<#
		.SYNOPSIS
			Returns the value of network bandwidth throttling setting for the specified machine.

		.DESCRIPTION
			Gets the setting in Mbps to use for replication. If this is set to 0, no throttling is applied.

		.PARAMETER InstanceId
			The CE instance to get the network bandwidth throttling setting for.
		
		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

        .EXAMPLE
			Get-CEMachineBandwidth -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708

			This the bandwidth throttling setting for the instance specified.

        .INPUTS
            System.Guid

        .OUTPUTS
           System.Int32
			
			The JSON representation of the returned object:
			{
				"bandwidthThrottling": 0
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$InstanceId,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$Path = "/projects/$ProjectId/machines/$InstanceId/bandwidthThrottling"

		try {
			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
			Write-Output -InputObject ($Result | Select-Object -ExpandProperty bandwidthThrottling)
		}
		catch [Exception] {
			throw "There was an issue retrieving bandwidth throttling setting: $($_.Exception.Message)"
		}
	}

	End {
	}
}

Function Set-CEMachineBandwidth {
	<#
		.SYNOPSIS
			Sets the value of the network bandwidth throttling setting for the specified machine.

		.DESCRIPTION
			The cmdlet sets or unsets the amount of bandwidth to be used for replication. The value is specified in Mbps. Specify a value of 0 to remove any
			existing throttling.

		.PARAMETER InstanceId
			The CE instance to set the network bandwidth throttling setting for.

		.PARAMETER BandwidthThrottling
			The value in Mbps to set for bandwidth throttling. A value of 0 removes any existing throttling.
		
		.PARAMETER ProjectId
			The project Id to use to set the configuration. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

        .EXAMPLE
			Set-CEMachineBandwidth -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708 -BandwidthThrottling 10

			This limits the amount of bandwidth to be used for replication to 10 Mbps for the specified instance.

		.EXAMPLE
			Set-CEMachineBandwidth -InstanceId 47d842b8-ebfa-4695-90f8-fb9ab686c708 -BandwidthThrottling 0

			This removes any throttling applied to the specified instance.

        .INPUTS
            None

        .OUTPUTS
           None or System.Int32
			
			The JSON representation of the returned object:
			{
				"bandwidthThrottling": 0
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$InstanceId,

		[Parameter(Mandatory = $true, Position = 1 )]
		[ValidateRange(0, [System.Int32]::MaxValue)]
		[System.Int32]$BandwidthThrottling,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$Uri = "/projects/$ProjectId/machines/$InstanceId/bandwidthThrottling"
		[System.String]$Body = ConvertTo-Json -InputObject @{bandwidthThrottling = $BandwidthThrottling}


		Write-Verbose -Message "Sending updated setting of:`r`n$Body"

		try {
			$Result = Invoke-CERequest -Path $Path -Method Patch -Body $Body -Session $Session -ExpectedResponseCode 200

			if ($PassThru)
			{
				Write-Output -InputObject ($Result | Select-Object -ExpandProperty bandwidthThrottling)
			}
		}
		catch [Exception] {
			throw "There was an issue retrieving bandwidth throttling setting: $($_.Exception.Message)"
		}
	}

	End {

	}
}

Function New-CEReplicationConfiguration {
	<#
		.SYNOPSIS
			Creates a new CE replication configuration.

		.DESCRIPTION
			This cmdlet is used to create a new CE replication configuration for a specific CE account. If you provide a config object or file, it is important to note that the parameters are extremely case sensitive!

			Use the following formatting for parameter names in a file or config object:

			{
			  "volumeEncryptionKey": "string",
			  "replicationTags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "disablePublicIp": true,
			  "subnetHostProject": "string",
			  "replicationServerType": "string",
			  "useLowCostDisks": true,
			  "computeLocationId": "string",
			  "cloudCredentials": "string",
			  "subnetId": "string",
			  "logicalLocationId": "string",
			  "bandwidthThrottling": 0,
			  "useDedicatedServer": true,
			  "zone": "string",
			  "replicatorSecurityGroupIDs": [
				"string"
			  ],
			  "usePrivateIp": true,
			  "region": "string",
			  "id": "string",
			  "proxyUrl": "string",
			  "volumeEncryptionAllowed": true,
			  "objectStorageLocation": "string",
			  "archivingEnabled": true,
			  "storageLocationId": "string"
			}

			You must also provide all parameters, and none of them can be null.

		.PARAMETER VolumeEncryptionKey
			AWS only. ARN to private key for volume encryption.

		.PARAMETER ReplicationTags
			AWS only. Tags that will be applied to every cloud resource created in the CloudEndure staging area.

		.PARAMETER DisablePublicIp
			When private IP is used, do not allocate public IP for replication server. Defaults to false.

		.PARAMETER SubnetHostProject
			GCP only. Host project of cross project network subnet.

		.PARAMETER ReplicationServerType
			The type of the replication server.

		.PARAMETER UseLowCostDisks
			Specify true to use low cost disks for eplication whenever possible.

		.PARAMETER ComputeLocationId
			VCENTER only.

		.PARAMETER CloudCredentials
			The ID for the cloudCredentials object containing the credentials to be used for accessing the target cloud. If this is not specified, the default credentials Id from the session will be used. 

		.PARAMETER SubnetId
			Subnet where replication servers will be created.

		.PARAMETER LogicalLocationId
			VCENTER only. vcenter = vmFolder

		.PARAMETER BandwidthThrottling
			Mbps to use for Data Replication (zero means no throttling).

		.PARAMETER UseDedicatedServer
			This will dedicate a single Replication Server for each source machine, instead of a single Replication Server for multiple source machines. 

		.PARAMETER Zone
			GCP and Azure ARM only. The zone to replicate into.

		.PARAMETER ReplicatorSecurityGroupIDs
			AWS only. The security groups that will be applied to the replication servers.
		
		.PARAMETER UsePrivateIp
			Should the CloudEndure agent access the replication server using its private IP address. Set this parameter to true to use a VPN, DirectConnect, ExpressRoute, or GCP Carrier Interconnect/Direct Peering.

		.PARAMETER ProxyUrl
			The full URI for a proxy (schema, username, password, domain, port) if required for the CloudEndure agent. Leave blank to not use a proxy.

		.PARAMETER VolumeEncryptionAllowed
			Specify if volume encryption is allowed.

		.PARAMETER ObjectStorageLocation
			AWS only. The bucket in AWS to store data.

		.PARAMETER ArchivingEnabled
			Is archiving enabled.

		.PARAMETER StorageLocationId
			The storage location id.

		.PARAMETER Config
			You can provide a replication config with these properties:

			{
			  "volumeEncryptionKey": "string",
			  "replicationTags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "disablePublicIp": true,
			  "subnetHostProject": "string",
			  "replicationServerType": "string",
			  "useLowCostDisks": true,
			  "computeLocationId": "string",
			  "cloudCredentials": "string",
			  "subnetId": "string",
			  "logicalLocationId": "string",
			  "bandwidthThrottling": 0,
			  "useDedicatedServer": true,
			  "zone": "string",
			  "replicatorSecurityGroupIDs": [
				"string"
			  ],
			  "usePrivateIp": true,
			  "region": "string",
			  "id": "string",
			  "proxyUrl": "string",
			  "volumeEncryptionAllowed": true,
			  "objectStorageLocation": "string",
			  "archivingEnabled": true,
			  "storageLocationId": "string"
			}

            You cannot specify an updated Source as part of the config file, you must specify that separately.

		.PARAMETER Path
			The path to the replication configuration json file.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER PassThru
			Specify to return the updated config to the pipeline.

		.EXAMPLE
			New-CEReplicationConfiguration -SubnetId "subnet-421d476c" -Target "us-east-1" -Source "Generic"

			Creates a new CE replication configuration to specify that replication will be sent to AWS US-East-1, replication servers should be deployed in subnet-421d476c, and the source is a generic location.

		.INPUTS
            None or System.Collections.Hashtable

        .OUTPUTS
           None or System.Management.Automation.PSCustomObject

			The JSON representation of the return value:
			{
			  "volumeEncryptionKey": "string",
			  "replicationTags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "disablePublicIp": true,
			  "subnetHostProject": "string",
			  "replicationServerType": "string",
			  "useLowCostDisks": true,
			  "computeLocationId": "string",
			  "cloudCredentials": "string",
			  "subnetId": "string",
			  "logicalLocationId": "string",
			  "bandwidthThrottling": 0,
			  "useDedicatedServer": true,
			  "zone": "string",
			  "replicatorSecurityGroupIDs": [
				"string"
			  ],
			  "usePrivateIp": true,
			  "region": "string",
			  "id": "string",
			  "proxyUrl": "string",
			  "volumeEncryptionAllowed": true,
			  "objectStorageLocation": "string",
			  "archivingEnabled": true,
			  "storageLocationId": "string"
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH", DefaultParameterSetName = "__AllParameterSets")]
	[OutputType([PSCustomObject])]
    Param(
		[Parameter(ParameterSetName = "Config", Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$Config = @{},

		[Parameter(ParameterSetName = "Path", Mandatory = $true)]
		[ValidateScript({
			Test-Path -Path $_
		})]
		[System.String]$Path,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$ReplicationTags = @(),

		[Parameter()]
		[System.Boolean]$DisablePublicIp = $false,

		[Parameter(ParameterSetName = "GCP")]
		[ValidateNotNullOrEmpty()]
		[System.String]$SubnetHostProject = [System.String]::Empty,

		[Parameter()]
		[System.Boolean]$UseLowCostDisks = $false,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$ComputeLocationId = [System.String]::Empty,

		[Parameter()]
		[ValidateNotNull()]
		[System.Guid]$CloudCredentials = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "VCENTER")]
		[ValidateNotNullOrEmpty()]
		[System.String]$LogicalLocationId = [System.String]::Empty,

		[Parameter()]
		[ValidateRange(0, [System.Int32]::MaxValue)]
		[System.Int32]$BandwidthThrottling = 0,

		[Parameter()]
		[System.Boolean]$UseDedicatedServer = $false,

		[Parameter(ParameterSetName = "GCP")]
		[Parameter(ParameterSetName = "Azure")]
		[ValidateNotNullOrEmpty()]
		[System.String]$Zone = [System.String]::Empty,

		[Parameter()]
		[System.Boolean]$UsePrivateIp = $false,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]$ProxyUrl = [System.String]::Empty,

		[Parameter()]
		[System.Boolean]$VolumeEncryptionAllowed = $false,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNullOrEmpty()]
		[System.String]$ObjectStorageLocation = [System.String]::Empty,

		[Parameter()]
		[System.Boolean]$ArchivingEnabled = $false,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[System.String]$StorageLocationId = [System.String]::Empty,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

	DynamicParam {

		# Create the dictionary 
        [System.Management.Automation.RuntimeDefinedParameterDictionary]$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		$DynSplat = @{}
		$ProjectSplat = @{}
		$SessionSplat = @{}

		if (-not [System.String]::IsNullOrEmpty($Session)) {
			$DynSplat.Add("Session", $Session)
			$ProjectSplat.Add("Session", $Session)
			$SessionSplat.Add("Session", $Session)
		}

		if ($ProjectId -ne $null -and $ProjectId -ne [System.Guid]::Empty)
		{
			$ProjectSplat.Add("Id", $ProjectId)
			$DynSplat.Add("ProjectId", $ProjectId)
		}

		$Project = Get-CEProject @ProjectSplat

		if ($CloudCredentials -ne $null -and $CloudCredentials -ne [System.Guid]::Empty)
		{
			$DynSplat.Add("CloudCredentials", $CloudCredentials)
		}
		else
		{
			$DynSplat.Add("CloudCredentials", $Project.cloudCredentialsIDs[0])
		}
	
		$Regions = Get-CECloudRegion @DynSplat
		$TargetRegionsSet = $Regions | Select-Object -ExpandProperty Id
		New-DynamicParameter -Name "TargetRegion" -Type ([System.String]) -ValidateSet $TargetRegionsSet -Mandatory -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

		$SourceRegionsSet = $Regions | Select-Object -ExpandProperty Id
		$SourceRegionsSet += "GENERIC"
		New-DynamicParameter -Name "SourceRegion" -Type ([System.String]) -ValidateSet $SourceRegionsSet -Mandatory -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

		# Only generate the rest of the dynamic parameters if a replication config wasn't specified
		if (-not $PSBoundParameters.ContainsKey("Config") -and -not $PSBoundParameters.ContainsKey("Path") -and $Config -ne @{})
		{
			$Type = Import-UnboundParameterCode -PassThru

			$TargetRegion = $Type.GetMethod("GetUnboundParameterValue").MakeGenericMethod([System.String]).Invoke($Type, @($PSCmdlet, "TargetRegion", -1))

			if (-not [System.String]::IsNullOrEmpty($TargetRegion))
			{
				$TargetCloudRegion = Get-CECloudRegion -Id $TargetRegion @DynSplat

				if ($TargetCloudRegion.Subnets.Length -gt 0)
				{
					$SubnetSet = $TargetCloudRegion.Subnets | Where-Object {$_.SubnetId -ne $null } | Select-Object -ExpandProperty SubnetId
					# Add default to allow user to specify the default subnet for the configured region
					$SubnetSet += "Default"

					New-DynamicParameter -Name "SubnetId" -Type ([System.String]) -ValidateSet $SubnetSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
				}
			}

			$CloudName = Get-CECloud -Id $Project.targetCloudId @SessionSplat | Select-Object -ExpandProperty Name

			switch ($CloudName)
			{
				"AWS" {
					# Creds may not have access to opt-in regions that get listed
					if (Get-Member -InputObject $TargetCloudRegion -MemberType Properties -Name "VolumeEncryptionKeys")
					{
						$KeySet = $TargetCloudRegion | Select-Object -ExpandProperty VolumeEncryptionKeys | Where-Object {$_.KeyArn -ne $null} | Select-Object -ExpandProperty KeyArn
						$KeySet += "Default"

						New-DynamicParameter -Name "VolumeEncryptionKey" -Type ([System.String]) -ValidateSet $KeySet -ParameterSets @("AWS") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}

					[System.String]$Key = $Type.GetMethod("GetUnboundParameterValue").MakeGenericMethod([System.String]).Invoke($Type, @($PSCmdlet, "SubnetId", -1))

					# The target region may not have been specified yet
					if ($TargetCloudRegion -ne $null)
					{
						$Subnet = $TargetCloudRegion.Subnets | Where-Object {$_.SubnetId -ieq $Key} | Select-Object -First 1 -ErrorAction SilentlyContinue
	
						# If the subnet is "Default", you won't be able to select a security group, so a new one will be created
						# Make sure there are security groups in this region and that we found a matching one
						# Subnet will be null if user selected "Default"
						if ($TargetCloudRegion.SecurityGroups -ne $null -and $TargetCloudRegion.SecurityGroups.Length -gt 0 -and $Subnet -ne $null -and $Subnet.Name -ine "Default")
						{
							# Get the network Id based on the selected subnet so we can get the right security groups as options
							[System.String[]]$SGSet = $TargetCloudRegion.SecurityGroups | Where-Object {$_.NetworkId -ieq $Subnet.NetworkId} | Select-Object -ExpandProperty SecurityGroupId

							New-DynamicParameter -Name "ReplicatorSecurityGroupIDs" -Type ([System.String[]]) -ParameterSets @("AWS") -ValidateSet $SGSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
						}
					}

					break
				}
				"GCP" {
					if ($TargetCloudRegion -ne $null -and $TargetCloudRegion.Zones.Length -gt 0)
					{
						$ZoneSet = $TargetCloudRegion.Zones
						# Add default to allow user to specify the default zone for the configured region
						$ZoneSet += "Default"

						New-DynamicParameter -Name "Zone" -Type ([System.String]) -ValidateSet $ZoneSet -ParameterSets @("GCP") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}
					break
				}
				"Azure" {
					if ($TargetCloudRegion -ne $null -and $TargetCloudRegion.Zones.Length -gt 0)
					{
						$ZoneSet = $TargetCloudRegion.Zones
						# Add default to allow user to specify the default zone for the configured region
						$ZoneSet += "Default"

						New-DynamicParameter -Name "Zone" -Type ([System.String]) -ValidateSet $ZoneSet -ParameterSets @("Azure") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
					}
					break
				}
			}
		}

        return $RuntimeParameterDictionary
	}

	Begin {		
	}

	Process {		
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		$Body = ""
		$ReplicationObject = [PSCustomObject]@{}
		
		switch ($PSCmdlet.ParameterSetName)
		{
			"Path" {
				$ReplicationObject = Get-Content -Path $Path -Raw | Convert-FromJson
				break
			}
			"Config" {
				$ReplicationObject = [PSCustomObject]$Config
				break
			}
			default {
				# This is going to take all of the parameters supplied, put them into a hash table, and then create a json
				# document that is the blueprint
				$Config = Convert-ParametersToHashtable -Parameters (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters `
					-ParameterSetName $PSCmdlet.ParameterSetName `
					-RuntimeParameterDictionary $RuntimeParameterDictionary `
					-BoundParameters $PSBoundParameters `
					-IncludeDefaults ` # All parameters have been given a default for this cmdlet
					-FunctionName $PSCmdlet.MyInvocation.InvocationName

				$ReplicationObject = [PSCustomObject]$Config
				break
			}
		}

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		$Splat = @{}

		if (-not [System.String]::IsNullOrEmpty($Session))
		{
			$Splat.Add("Session", $Session)
		}

		$Project = Get-CEProject -Id $ProjectId @Splat

		if (-not (Get-Member -InputObject $ReplicationObject -MemberType Properties -Name "cloudCredentials"))
		{
			$ReplicationObject | Add-Member -MemberType NoteProperty -Name "cloudCredentials" -Value $Project.CloudCredentialsIDs[0]
		}

		# It may be possible this dynamic param was never specified
		if (-not (Get-Member -InputObject $ReplicationObject -MemberType Properties -Name "replicatorSecurityGroupIDs"))
		{
			$ReplicationObject | Add-Member -MemberType NoteProperty -Name "replicatorSecurityGroupIDs" -Value @()	
		}

		$SecurityGroupIds = $ReplicationObject.ReplicatorSecurityGroupIDs

		if ($ReplicationObject.CloudCredentials -eq [System.Guid]::Empty)
		{
			$ReplicationObject.CloudCredentials = $Project.CloudCredentialsIDs[0]
		}

		if ($ReplicationObject.SubnetId -ieq "Default")
		{
			$ReplicationObject.SubnetId = ""
		}

		$ReplicationObject = $ReplicationObject | Select-Object -Property * -ExcludeProperty "TargetRegion", "SourceRegion", "ReplicatorSecurityGroupIDs"

		# Must specify the region for the target since this won't be set yet in the project
		# If the project has a target region, it's because it has an associated replication
		# configuration, which means we wouldn't be creating a new one
		$ReplicationObject | Add-Member -MemberType NoteProperty -Name "region" -Value $PSBoundParameters["TargetRegion"]

		$ReplicationObject | Add-Member -MemberType NoteProperty -Name "replicatorSecurityGroupIDs" -Value $SecurityGroupIds
		
		$Body = ConvertTo-Json -InputObject $ReplicationObject
		Write-Verbose -Message "Sending new config:`n$Body"

		[System.String]$UrlPath = "/projects/$ProjectId/replicationConfigurations"

		$ErrorHandling = {
			Param($StatusCode, $Content, $ErrorMessage)
			
			switch ($StatusCode) {
				201 {	
					Write-Verbose -Message $Content
					Write-Output -InputObject (ConvertFrom-Json -InputObject $Content)
					break
				}
				400 {
					throw "There is a conflict in the replication configuration. This can be due to: subnet ID which does not exist in the region, security groups that are not in the same network as the subnet, etc."
				}
				default {
					# Make sure we don't send the patch request if this failed
					throw "Failed to create new Replication Configuration with error: $ErrorMessage"
				}
			}
		}

		$Result = Invoke-CERequest -Path $UrlPath -Method Post -Body $Body -Session $Session -ErrorHandling $ErrorHandling

		if ($PassThru)
		{
			Write-Output -InputObject $Result
		}

		# After creating the new replication configuration, we need to patch the project
		# with the replication configuration id and source region id

		$UrlPath = "/projects/$ProjectId"
		$ProjectContent = @{replicationConfiguration = $Result.Id; sourceRegion = $PSBoundParameters["SourceRegion"] }

		if ($ProjectContent["sourceRegion"] -ieq "GENERIC")
		{
			$AccountInfo = Get-CEAccountExtendedInfo @Splat 
			$ProjectContent["sourceRegion"] = $AccountInfo.GenericRegion.Id
		}

		$ProjectBody = ConvertTo-Json -InputObject $ProjectContent

		Write-Verbose -Message "Patching project $ProjectId`:`n$ProjectBody"

		$Result = Invoke-CERequest -Path $UrlPath -Method Patch -Body $ProjectBody -Session $Session -ExpectedResponseCode 200
	}

	End {
	}
}

Function Get-CEReplicationConfiguration {
	<#
        .SYNOPSIS
           Gets the replication configuration.

        .DESCRIPTION
            The cmdlet retrieves information about the replication configuration.

		.PARAMETER Id
			The id of the replication configuration to retrieve. If this is not specified, all replication configurations will be returned.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CEReplicationConfiguration

            Retrieves the replication configuration of the current account.

        .INPUTS
            None or System.Guid

        .OUTPUTS
			System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			The JSON representation of the array:
			[
				{
				  "volumeEncryptionKey": "string",
				  "replicationTags": [
					{
					  "key": "string",
					  "value": "string"
					}
				  ],
				  "disablePublicIp": true,
				  "subnetHostProject": "string",
				  "replicationServerType": "string",
				  "useLowCostDisks": true,
				  "computeLocationId": "string",
				  "cloudCredentials": "string",
				  "subnetId": "string",
				  "logicalLocationId": "string",
				  "bandwidthThrottling": 0,
				  "useDedicatedServer": true,
				  "zone": "string",
				  "replicatorSecurityGroupIDs": [
					"string"
				  ],
				  "usePrivateIp": true,
				  "region": "string",
				  "id": "string",
				  "proxyUrl": "string",
				  "volumeEncryptionAllowed": true,
				  "objectStorageLocation": "string",
				  "archivingEnabled": true,
				  "storageLocationId": "string"
				}
			]
			
        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    Param(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName="GetById")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo["DefaultProjectId"]
		}

		[System.String]$UrlPath = "/projects/$ProjectId/replicationConfigurations"

		[System.Int32]$ResultCount = 0
		[System.Boolean]$Found = $false

		do {
			[System.String]$QueryString = "?offset=$Offset&limit=$Limit"
			[System.String]$TempUri = "$UrlPath$QueryString"

			Write-Verbose -Message "Querying replication configurations from $Offset to $($Offset + $Limit)."

			try {
				$Result = Invoke-CERequest -Path $TempUri -Method Get -Session $Session -ExpectedResponseCode 200
			}
			catch [Exception] {
				throw "There was an issue listing the replication configurations: $($_.Exception.Message)"
			}

			[PSCustomObject[]]$Content = $Result.Items
			$ResultCount = $Result.Items.Length

			switch -wildcard ($PSCmdlet.ParameterSetName)
			{
				"Get*" {

					$Filter = {$_.Id -ieq $Id.ToString()}

					$ReplConfig = $Content | Where-Object $Filter

					if ($ReplConfig -ne $null)
					{
						Write-Output -InputObject ([PSCustomObject]($ReplConfig | Select-Object -First 1))
						$Found = $true
						break
					}
					else
					{
						$Offset += $Limit
					}

					break
				}
				"List" {
					Write-Output -InputObject $Content
					$ResultCount = $Limit - 1 # Make sure we break the do loop
					break
				}
				default {
					throw "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
				}
			}

		} while ($ResultCount -ge $Limit)

		if ($PSCmdlet.ParameterSetName -like "Get*" -and -not $Found)
		{
			throw "The replication configuration with Id $Id was not found."
		}
	}

    End {
    }
}

Function Set-CEReplicationConfiguration {
    <#
		.SYNOPSIS
			Sets the CE replication configuration.

		.DESCRIPTION
			This cmdlet is used to set the CE replication configuration options for a specific CE account.

			Modifying volumeEncryptionKey or modifying cloudCredentials to ones matching a different cloud account will result in replication restarting from initial sync.

			This cmdlet will let you specify both Config and some other values, like -UsePrivateIp. If you specify any additional configuration parameters, they will be ignored.

		.PARAMETER Id
			The replication configuration id.

		.PARAMETER CloudCredentials
			The ID for the cloudCredentials object containing the credentials to be used for accessing the target cloud. If this is not specified, the default credentials Id from the session will be used. 

		.PARAMETER ProxyUrl
			The full URI for a proxy (schema, username, password, domain, port) if required for the CloudEndure agent. Leave blank to not use a proxy.

		.PARAMETER SubnetId
			Specify the subnet Id that the replication servers will be launched in.

		.PARAMETER UsePrivateIp
			Set this parameter to true to use a VPN, DirectConnect, ExpressRoute, or GCP Carrier Interconnect/Direct Peering.

		.PARAMETER VolumeEncryptionKey
			AWS only. ARN to private key for volume encryption.

		.PARAMETER ReplicationTags
			AWS only. Specify the tags that will be applied to CE replication resources.

		.PARAMETER SubnetHostProject
			GCP only. Host project of cross project network subnet.

		.PARAMETER Config
			You can provide a replication config with these properties:

			{
			  "volumeEncryptionKey": "string",
			  "replicationTags": [
				{
				  "key": "string",
				  "value": "string"
				}
			  ],
			  "subnetHostProject": "string",
			  "replicatorSecurityGroupIDs": [
				"string"
			  ],
			  "usePrivateIp": true,
			  "proxyUrl": "string",
			  "cloudCredentials": "string",
			  "subnetId": "string"
			}

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			Specify to return the updated config to the pipeline.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.EXAMPLE
			Set-CEReplicationConfiguration -Id 8cdf36d4-6668-44a9-9cfe-16cb93538a79 -SubnetId "subnet-421d476c"

			Updates the existing replication configuration to specify that replication servers should be deployed in subnet-421d476c.

		.INPUTS
            None

        .OUTPUTS
           None or System.Management.Automation.PSCustomObject

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid]$Id,

		[Parameter(ParameterSetName = "Config", Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$Config = @{},

		[Parameter()]
		[ValidateNotNull()]
		[System.Guid]$CloudCredentials = [System.Guid]::Empty,

        [Parameter()]
        [ValidateNotNull()]
        [System.String]$ProxyUrl,

        [Parameter()]
        [System.Boolean]$UsePrivateIp,

		[Parameter(ParameterSetName = "AWS")]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$ReplicationTags,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

	DynamicParam {
		if ($Config -eq $null -or $Config -eq @{})
		{
			if (-not [System.String]::IsNullOrEmpty($Session)) {
				$DynSessionInfo = $script:Sessions.Get_Item($Session)
				$DynSession = $Session
			}
			else {
				$DynSessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
				$DynSession = $DynSessionInfo.User.Username
			}

			$DynSplat = @{
				"Session" = $DynSession
			}

			if ($ProjectId -ne $null -and $ProjectId -ne [System.Guid]::Empty)
			{
				$DynSplat.Add("ProjectId", $ProjectId)
			}

			[System.Collections.Hashtable]$CECloud = Get-CETargetCloud @DynSplat | ConvertTo-Hashtable

			# Create the dictionary 
			$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary
		
			if ($Id -ne $null -and $Id -ne [System.Guid]::Empty) 
			{
				if ($CECloud.Subnets.Length -gt 0) 
				{
					#region SubnetId

					# Allow user to specify either the long name or the subnet id in the parameter
					[System.String[]]$SubnetSet = $CECloud.Subnets | Select-Object -ExpandProperty Name
					$SubnetSet += $CECloud.Subnets | Select-Object -ExpandProperty SubnetId

					New-DynamicParameter -Name "SubnetId" -Type ([System.String]) -ParameterSets @("AWS") -ValidateSet $SubnetSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

					#endregion
				}

				switch ($CECloud.Cloud)
				{
					"AWS" {

						if ($CECloud.VolumeEncryptionKeys.Length -gt 0)
						{
							#region KMS

							[System.Collections.ArrayList]$KMSSet = $CECloud.VolumeEncryptionKeys | Where-Object {$_.KeyArn -ne $null } | Select-Object -ExpandProperty KeyArn
							$KMSSet += "Default"
							$KMSSet += [System.String]::Empty

							New-DynamicParameter -Name "VolumeEncryptionKey" -Type ([System.String[]]) -ParameterSets @("AWS") -ValidateSet $KMSSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

							#endregion
						}

						$Type = Import-UnboundParameterCode -PassThru
						# The subnet Id here is the verbose version of the subnet selected by the user
						[System.String]$SubnetId = $Type.GetMethod("GetUnboundParameterValue").MakeGenericMethod([System.String]).Invoke($Type, @($PSCmdlet, "SubnetId", -1))
			
						if ([System.String]::IsNullOrEmpty($SubnetId))
						{
							[System.Collections.Hashtable]$ExistingConfig = Get-CEReplicationConfiguration -Id $Id @DynSplat | ConvertTo-Hashtable

							if (-not [System.String]::IsNullOrEmpty($ExistingConfig.SubnetId))
							{
								$SubnetId = $ExistingConfig.SubnetId
							}
						}

						$VpcId = $CECloud.Subnets |
							Where-Object {$_.Name -ieq $SubnetId -or $_.Id -ieq $SubnetId} | 
							Select-Object -ExpandProperty NetworkId -ErrorAction SilentlyContinue

						# If we found the subnet, and we found the VPC, populate security groups
						# If it wasn't found, either the subnet provided was "Default" or not a recognized value
						# then we won't populate security groups since the only option is create new
						if (-not [System.String]::IsNullOrEmpty($VpcId))
						{
							#region SecurityGroups
							$SGSet = $CECloud.SecurityGroups | Where-Object {$_.NetworkId -ieq $VpcId} | Select-Object -ExpandProperty SecurityGroupId
							$SGSet += [System.String]::Empty

							New-DynamicParameter -Name "ReplicatorSecurityGroupIDs" -Type ([System.String]) -ParameterSets @("AWS") -ValidateSet $SGSet -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null

							#endregion
						}

						break
					}
					"GCP" {
						# Do nothing
						break
					}
					"Azure" {
						# Do nothing
						break
					}
					default {
						throw "The cloud environment $($CECloud.Cloud) is not supported by this cmdlet yet."
					}
				}
			}

			return $RuntimeParameterDictionary
		}
	}

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			[System.Collections.Hashtable]$SessSplat = @{
				"Session" = $Session
			}

			if ($ProjectId -ne [System.Guid]::Empty)
			{
				$SessSplat.Add("ProjectId", $ProjectId)
			}

			[System.Collections.Hashtable]$ExistingConfig = Get-CEReplicationConfiguration -Id $Id @SessSplat | ConvertTo-Hashtable

			# If a config hashtable wasn't provided, build one for the parameter set being used
			if ($PSCmdlet.ParameterSetName -ne "Config")
			{
				# Convert only the non-common parameters specified into a hashtable
				$Params = @{}

				foreach ($Item in (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key)})
                {
					[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
                    $Params.Add($Item.Key, $Sets)
                }

                $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
                    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

                    if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                    {
						[System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
						$Params.Add($Param.Name, $ParameterSets)
                    }
                }

				$Config = @{}

				# Get the parameters for the command
				foreach ($Item in $Params.GetEnumerator())
				{
					# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
					if ($Item.Value.Contains($PSCmdlet.ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
					{
						# Check to see if it was supplied by the user
						if ($PSBoundParameters.ContainsKey($Item.Key))
						{
							# If it was, add it to the config object

							if ($Item.Key -ieq "ReplicationTags")
							{
								[System.Collections.Hashtable[]]$TagsToAdd = @()
								# We need to convert the hashtable to the tag key/value structure
								$PSBoundParameters[$Item.Key].GetEnumerator() | ForEach-Object {
									$TagsToAdd += @{"key" = $_.Key; "value" = $_.Value}
								}

								$Config.Add("replicationTags", $TagsToAdd)
							}
							elseif ($Item.Key -ieq "SubnetId") 
							{
								[System.String]$SubnetId = $CECloud.Subnets | 
									Where-Object {$_.Name -ieq $PSBoundParameters["SubnetId"] -or $_.Id -ieq $PSBoundParameters["SubnetId"]} | 
									Select-Object -First 1 -ExpandProperty Id

								if (-not [System.String]::IsNullOrEmpty($SubnetId))
								{
									$Config.Add("subnetId", $SubnetId)
								}
							}
							else {
								$Config.Add($Item.Key.Substring(0, 1).ToLower() + $Item.Key.Substring(1), $PSBoundParameters[$Item.Key])
							}
						}
					}
				}
			}

			# Merge the original and new blueprint
			[System.Collections.Hashtable]$NewConfig = Merge-HashTables -Source $ExistingConfig -Update $Config

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/replicationConfigurations/$($Id.ToString())"

			$ConfirmMessage = "Are you sure you want to update the replication configuration?"

			$WhatIfDescription = "Updated configuration to $(ConvertTo-Json -InputObject $NewConfig)"
			$ConfirmCaption = "Update Replication Configuration"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Sending updated config $(ConvertTo-Json -InputObject $NewConfig)"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Patch -Body (ConvertTo-Json -InputObject $NewConfig) -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				switch ($StatusCode)
				{
					200 {
						if ($PassThru) 
						{
							Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
						}

						break
					}
					400 {
						throw "There is a conflict in the replication configuration. This can be due to: subnet ID which does not exist in the region, security groups that are not in the same network as the subnet, etc."
					}
					default {
						throw "There was an issue updating the replication configuration: $StatusCode $Reason - $($Result.Content)"
					}
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Remove-CEReplicationConfiguration {
	<#
		.SYNOPSIS
			Removes a replication configuration. NOT YET SUPPORTED!

		.DESCRIPTION
			This cmdlet removes a specified replication configuration. NOT YET SUPPORTED!

		.PARAMETER Id
			The id of the replication configuration to remove.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			If specified, the deleted configuration is returned to the pipeline.

		.EXAMPLE
			Remove-CEReplicationConfiguration -Id 2ff58f32-cb82-4c41-accc-3001a104c560

			Removes the replication configuration with the provided Id.

		.INPUTS
			System.Guid

		.OUPUTS
			None or System.Management.Automation.PSCustomObject

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
	#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid]$Id,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty,

		[Parameter()]
		[Switch]$PassThru
    )

    Begin {
		throw "Cmdlet not implemented."
    }

    Process {
        $SessionInfo = Get-CESessionOrDefault -Session $Session

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

        [System.String]$Uri = "/projects/$ProjectId/replicationConfigurations/$($Id.ToString())"

		$ConfirmMessage = "You are about to remove replication configuration $Id."
		$WhatIfDescription = "Removed replication configuration $Id"
		$ConfirmCaption = "Delete CE Replication Configuration"
		
		if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
		{
			try {
				$Result = Invoke-CERequest -Path $UrlPath -Method Delete -Session $Session -ExpectedResponseCode 204

				if ($PassThru)
				{
					Write-Output -InputObject $Result
				}
			}
			catch [Exception] {
				throw $_.Exception
			}
		}
    }

    End {
    }
}

#endregion

#region User

Function Get-CEUser {
	<#
        .SYNOPSIS
			Gets the current CloudEndure user information.

        .DESCRIPTION
			The cmdlet gets the current CloudEndure user information

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CEUser

            Gets the current user information.

        .INPUTS
            None

        .OUTPUTS
           PSCustomObject

			This is a JSON representation of the returned value:
			{
			  "username": "user@example.com",
			  "status": "PENDING",
			  "account": "string",
			  "roles": [
				"USER"
			  ],
			  "settings": {
				"sendNotifications": {
				  "projectIDs": [
					"string"
				  ]
				}
			  },
			  "apiToken": "string",
			  "hasPassword": true,
			  "termsAccepted": true,
			  "id": "string",
			  "selfLink": "string"
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {     
		[System.String]$Path = "/me"

		try {
			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
			Write-Output -InputObject $Result
		}
		catch [Exception] {
			throw "There was an issue retrieving the user info: $($_.Exception.Message)"
		}	
    }

    End {
    }
}

Function Set-CEConsolePassword {
	<#
		.SYNOPSIS
			Updates the password associated with the console logon.

		.DESCRIPTION
			The cmdlet updates the CE account password used to logon to the console.

		.PARAMETER OldPassword
			The current password for the account.

		.PARAMETER NewPassword
			The new password for the account. It must 8 characters or more, 1 upper, 1 lower, 1 numeric, and 1 special character.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Set-CEConsolePassword -OldPassword MyOldP@$$w0rd -NewPassword @$3cureP@$$w0rd
			
			The cmdlet updates the password.

		.INPUTS
			PSObject

		.OUTPUTS
			None

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType()]
	Param(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$OldPassword,

		[Parameter(Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$_ -ne $OldPassword
		})]
		[ValidatePattern("^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[$@$!%*?&])[A-Za-z\d$@$!%*?&]{8,}")]
		[System.String]$NewPassword,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		[System.String]$Path = "/changePassword"

		[System.Collections.Hashtable]$Body = @{
			"oldPassword" = $OldPassword;
			"newPassword" = $NewPassword
		}

		$ConfirmMessage = "Are you sure you want to update the console password?"
		$WhatIfDescription = "Updated password for $Session."
		$ConfirmCaption = "Update Console Password for $Session"

		if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
		{
			Write-Verbose -Message "Sending updated config:`r`n $(ConvertTo-Json -InputObject $Body)"
			

			$ErrorHandling = {
				Param($StatusCode, $Content, $ErrorMessage)
				
				switch ($StatusCode)
				{
					204 {
						Write-Verbose -Message "Password successfully updated."
						break
					}
					400 {
						throw "Password change did not succeed (e.g. Old password mismatch).`r`n$Content"
					}
					default {
						throw "There was an issue with changing the password: $ErrorMessage"
					}
				}
			}

			$Result = Invoke-CERequest -Path $Path -Method Post -Body ($Body | ConvertTo-Json) -Session $Session -ErrorHandling $ErrorHandling
		}
	}

	End {
	}
}

Function Set-CEEmailNotifications {
	<#
        .SYNOPSIS
			Sets the email notification status.

        .DESCRIPTION
			The cmdlet either disables or enables email notifications.

		.PARAMETER Enabled
			Specifies that email notifications will be enabled for the specified projects.

		.PARAMETER Disabled
			Specifies that email notifications will be disabled for the specified projects.

		.PARAMETER Ids
			The project Ids to enable or disable notifications for. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			Will pass through the updated user config to the pipeline.
            
        .EXAMPLE
            Set-CEEmailNotifications -Enabled

			Enables email notifications on the default for the current user.

		.EXAMPLE
			Set-CEEmailNotifications -Disabled -Ids @("c933c984-6dae-431b-a1f4-3063e66c438f")

			Disables notifications for the specified project in the current user's settings.

        .INPUTS
            None

        .OUTPUTS
			None or System.Management.Automation.PSCustomObject

			This is a JSON representation of the returned value

			{
			  "username": "user@example.com",
			  "account": "string",
			  "agentInstallationToken": "string",
			  "settings": {
				"sendNotifications": {
				  "projectIds": [
					"string"
				  ]
				}
			  },
			  "id": "string",
			  "selfLink": "string"
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
		[Parameter(Mandatory = $true, ParameterSetName = "Enabled")]
		[Switch]$Enabled,

		[Parameter(Mandatory = $true, ParameterSetName = "Disabled")]
		[Switch]$Disabled,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid[]]$Ids = @(),

		[Parameter()]
		[Switch]$PassThru,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {

		$SessionInfo = Get-CESessionOrDefault -Session $Session

		[System.String]$Path = "/users/$($SessionInfo.UserId)"

		if ($Enabled) 
		{
			if ($Ids.Length -eq 0)
			{
				$Ids += $SessionInfo.DefaultProjectId
			}
		}
		else # Disable notifications
		{
			$CurrentSetup = Get-CEUser -Session $Session
			[System.Guid[]]$CurrentProjects = $CurrentSetup.Settings.SendNotifications.ProjectIds
			
			[System.Guid[]]$RemaingProjects = @()

			# Remove the Ids specified by the user by adding the current items that don't match
			# to a temporary array
			foreach ($Id in $CurrentProjects)
			{
				if (-not $Ids.Contains($Id))
				{
					$RemaingProjects += $Id
				}
			}

			# Iterate again to warn the user if they specified projects that weren't currently enabled
			foreach ($Id in $Ids)
			{
				if (-not $CurrentProjects.Contains($Id))
				{
					Write-Warning -Message "Could not find a project $Id that was enabled for notifications for the current user."
				}
			}

			$Ids = $RemaingProjects
		}

		[System.String]$Body = ConvertTo-Json -InputObject @{
			"username" = $SessionInfo.User.username; 
			"settings" = @{"sendNotifications" = @{"projectIDs" = $Ids}}
		} -Depth 3

		Write-Verbose -Message "Setting email notifications update:`r`n$Body"
		
		$ErrorHandling = {
			Param(
				$StatusCode,
				$Content,
				$ErrorMessage,
				$Enabled,
				$Username
			)

			switch ($StatusCode)
			{
				200 {
					if ($Enabled) 
					{
						Write-Verbose -Message "Email notifications enabled for $Username."
					}
					else 
					{
						Write-Verbose -Message "Email notifications disabled for $Username."
					}

					Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Content))

					break
				}
				401 {
					throw "Tried patching a user different to the currently logged in one.`r`n$Content"
				}
				404 {
					throw "Cannot apply the project ids provided.`r`n$Content"
				}
				default {
					throw "Email notifications could not be set properly, $ErrorMessage"
				}
			}
		}

		try {
			$Result = Invoke-CERequest -Body $Body -Path $Path -Method Patch -Session $Session -ErrorHandling $ErrorHandling -ErrorHandlingArgs @($Enabled, $SessionInfo.User.username)
			Write-Output -InputObject $Result
		}
		catch [Exception] {
			throw "There was an issue setting the notification settings: $($_.Exception.Message)"
		}
    }

    End {
    }
}

#endregion

#region Accounts

Function Get-CEAccount {
	<#
		.SYNOPSIS
			CloudEndure service account information.

		.DESCRIPTION
			CloudEndure service account information.

		.PARAMETER AccountId
			The account Id to retrieve information about. This defaults to the user account retrieved during login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Get-CEAccount

			Gets the account data.

		.INPUTS
			None

		.OUTPUTS
			System.Management.Automation.PSCustomObject

			This is a JSON representation of the returned object.
			{
				"inviteTokenExpiryMinutes": 0,
				"allowArchivingDefaultValue": true,
				"perAccountUserPool": true,
				"isGcpSelfService": true,
				"isDrTrial": true,
				"isArmSelfService": true,
				"isAwsSelfService": true,
				"samlSettings": {
					"identityProviderCertificate": "string",
					"identityProviderUrl": "string",
					"identityProviderID": "string"
				},
				"isRightSizingEnabled": true,
				"defaultLicenseType": "MIGRATION",
				"maxProjectsAllowed": 0,
				"ceAdminProperties": {
					"state": "ACTIVE",
					"version": "string",
					"accountOwnerUsername": "string",
					"apisPerMinute": 0,
					"comments": "string",
					"history": "string"
				},
				"ownerId": "string",
				"isMedOne": true,
				"id": "string"
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
	#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$AccountId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {

		if ($AccountId -eq [System.Guid]::Empty)
		{
			$SessionInfo = Get-CESessionOrDefault -Session $Session
			$AccountId = [System.Guid]::Parse($SessionInfo["User"].account)
		}

		[System.String]$Path = "/accounts/$AccountId"

		try {
			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
			Write-Output -InputObject $Result
		}
		catch [Exception] {
			throw "There was an issue retrieving the CE account: $($_.Exception.Message)"
		}
	}

	End {
	}
}

Function Get-CEAccountExtendedInfo {
	 <#
		.SYNOPSIS
			Returns the extended current account information.

		.DESCRIPTION
			This cmdlet returns the extended current account information.

			-Account (Features & Id)
			-Clouds (Configured cloud environments)
			-Generic Region
			-DateTime (Current time)
			-User
			-License
			-Projects
			-ReplicationConfiguration

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Get-CEAccountExtendedInfo

			Gets the extended account information

		.INPUTS
			None

		.OUTPUTS
			PSCustomObject

			This is a JSON representation of the return object:

			{
			  "account": {
				"inviteTokenExpiryMinutes": 0,
				"allowArchivingDefaultValue": true,
				"perAccountUserPool": true,
				"isGcpSelfService": true,
				"isDrTrial": true,
				"isArmSelfService": true,
				"isAwsSelfService": true,
				"samlSettings": {
				  "identityProviderCertificate": "string",
				  "identityProviderUrl": "string",
				  "identityProviderID": "string"
				},
				"isRightSizingEnabled": true,
				"defaultLicenseType": "MIGRATION",
				"maxProjectsAllowed": 0,
				"ceAdminProperties": {
				  "state": "ACTIVE",
				  "version": "string",
				  "accountOwnerUsername": "string",
				  "apisPerMinute": 0,
				  "comments": "string",
				  "history": "string"
				},
				"ownerId": "string",
				"isMedOne": true,
				"id": "string"
			  },
			  "clouds": {
				"items": [
				  {
					"id": "string",
					"roles": [
					  "SOURCE"
					],
					"name": "AWS"
				  }
				]
			  },
			  "genericRegion": {
				"subnets": [
				  {
					"subnetId": "string",
					"networkId": "string",
					"name": "string"
				  }
				],
				"placementGroups": [
				  "string"
				],
				"scsiAdapterTypes": [
				  "string"
				],
				"instanceTypes": [
				  "string"
				],
				"zones": [
				  "string"
				],
				"volumeEncryptionKeys": [
				  "string"
				],
				"cloud": "string",
				"securityGroups": [
				  {
					"networkId": "string",
					"securityGroupId": "string",
					"name": "string"
				  }
				],
				"logicalLocations": [
				  {
					"locationId": "string",
					"name": "string"
				  }
				],
				"staticIps": [
				  "string"
				],
				"maxCpusPerMachine": 0,
				"networkInterfaces": [
				  {
					"subnetId": "string",
					"name": "string",
					"privateIp": "string"
				  }
				],
				"computeLocations": [
				  {
					"isEncryptionSupported": true,
					"locationId": "string",
					"name": "string"
				  }
				],
				"name": "string",
				"storageLocations": [
				  {
					"locationId": "string",
					"name": "string"
				  }
				],
				"iamRoles": [
				  "string"
				],
				"id": "string",
				"maxCoresPerMachineCpu": 0,
				"dedicatedHosts": [
				  "string"
				],
				"networkAdapterTypes": [
				  "string"
				],
				"maxMbRamPerMachine": 0
			  },
			  "dateTime": {
				"dateTime": "2019-10-15T16:25:26Z"
			  },
			  "user": {
				"username": "user@example.com",
				"status": "PENDING",
				"account": "string",
				"roles": [
				  "USER"
				],
				"settings": {
				  "sendNotifications": {
					"projectIDs": [
					  "string"
					]
				  }
				},
				"apiToken": "string",
				"hasPassword": true,
				"termsAccepted": true,
				"id": "string",
				"selfLink": "string"
			  },
			  "projects": {
				"items": [
				  {
					"targetCloudId": "string",
					"agentInstallationToken": "string",
					"name": "string",
					"usersIDs": [
					  "string"
					],
					"type": "MIGRATION",
					"replicationReversed": true,
					"sourceCloudCredentialsId": "string",
					"cloudCredentialsIDs": [
					  "string"
					],
					"sourceRegion": "string",
					"licensesIDs": [
					  "string"
					],
					"ceAdminProperties": {
					  "comments": "string",
					  "history": "string"
					},
					"replicationConfiguration": "string",
					"sourceCloudId": "string",
					"id": "string",
					"features": {
					  "awsExtendedHddTypes": true,
					  "allowRecoveryPlans": true,
					  "allowArchiving": true,
					  "isDemo": true,
					  "drTier2": true,
					  "allowByolOnDedicatedInstance": true,
					  "pit": true
					}
				  }
				]
			  },
			  "isNewlyRegistered": true,
			  "replicationConfigurations": {
				"items": [
				  {
					"volumeEncryptionKey": "string",
					"replicationTags": [
					  {
						"key": "string",
						"value": "string"
					  }
					],
					"disablePublicIp": true,
					"subnetHostProject": "string",
					"replicationServerType": "string",
					"useLowCostDisks": true,
					"computeLocationId": "string",
					"cloudCredentials": "string",
					"subnetId": "string",
					"logicalLocationId": "string",
					"bandwidthThrottling": 0,
					"useDedicatedServer": true,
					"zone": "string",
					"replicatorSecurityGroupIDs": [
					  "string"
					],
					"usePrivateIp": true,
					"region": "string",
					"id": "string",
					"proxyUrl": "string",
					"volumeEncryptionAllowed": true,
					"objectStorageLocation": "string",
					"archivingEnabled": true,
					"storageLocationId": "string"
				  }
				]
			  }
			}

		 .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
	#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
		[System.String]$Path = "/extendedAccountInfo"

		try {
			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
			Write-Output -InputObject $Result
		}
		catch [Exception] {
			throw "There was an issue retrieving the account summary: $($_.Exception.Message)"
		}	
    }

    End {
    }
}

#endregion

#region Licenses

Function Get-CELicense {
	<#
        .SYNOPSIS
           Gets the current state of license information.

        .DESCRIPTION
            The cmdlet lists the license information about the specified account.

		.PARAMETER Id
			The Id of the license to retrieve.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CELicense

            Retrieves the licenses in the account using the default session context.

        .INPUTS
            None

        .OUTPUTS
			System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			This is a JSON representation of the returned array:
			[
				{
				  "count": 0,
				  "durationFromStartOfUse": "string",
				  "used": 0,
				  "expirationDateTime": "2017-09-06T01:39:46Z",
				  "type": "MIGRATION",
				  "id": "string"
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/15/2019
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
    [OutputType([System.Management.Automation.PSCustomObject[]])]
    Param(
		[Parameter(ValueFromPipeline = $true, ParameterSetName = "Get")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
		[System.String]$Path = "/licenses"

		switch ($PSCmdlet.ParameterSetName)
		{
			"Get" {
				if ($Id -ne [System.Guid]::Empty)
				{
					$Path += "/$($Id.ToString())"
				}
				break
			}
			"List" {
				if ($Offset -gt 0 -or $Limit -lt 1500)
				{
					$QueryString = [System.String]::Empty

					if ($Offset -gt 0)
					{
						$QueryString += "&offset=$Offset"
					}

					if ($Limit -lt 1500)
					{
						$QueryString += "&limit=$Limit"
					}

					# Remove the first character which is an unecessary ampersand
					$Path += "?$($QueryString.Substring(1))"
				}
				break
			}
			default {
				throw "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
			}
		}

		try {

			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
			
			[PSCustomObject[]]$Return = @()

			if ($Id -ne [System.Guid]::Empty)
			{
				$Return += $Result
			}
			else 
			{
				$Return += $Result.Items
			}

			# Force PowerShell to stop unboxing 1 item arrays
			# Cannot be used with Write-Output
			,$Return
		}
		catch [Exception] {
			throw "There was an issue retrieving the license information: $($_.Exception.Message)"
		}	
    }

    End {
    }
}

#endregion

#region Project

Function New-CEProject {
	<#
		.SYNOPSIS
			Creates a new CloudEndure project.

		.DESCRIPTION
			Creates a new CloudEndure project.

		.PARAMETER Config
			The config to use to create the project.

			{
			  "targetCloudId": "string",
			  "name": "string",
			  "cloudCredentialsIDs": [
				"string"
			  ],
			  "sourceRegion": "string",
			  "replicationConfiguration": "string"
			}

		.PARAMETER Target
			The Name of the target cloud environment to use.

		.PARAMETER Name
			The name of the project.

		.PARAMETER CloudCredentialsIDs
			An array of 1 cloud credentials to use. This defaults to the current session.
		
		.PARAMETER ReplicationConfiguration
			The Id of the replication configuration for the project to use.

		.PARAMETER Source
			The Name of the source cloud environment to use.

		.PARAMETER PassThru
			If specified, the updated configuration is returned to the pipeline.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			New-CEProject -Source "Generic" -Target "AWS" -Name "MyAWSMigration" -ReplicationConfiguration 0cd58880-2ba0-469c-95f6-ed851f034145

			Creates a new project for migrating from a Generic source to AWS.

		.INPUTS
			None or System.Collections.Hashtable

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject

			The JSON representation of the returned object:
			{
			  "targetCloudId": "string",
			  "agentInstallationToken": "string",
			  "name": "string",
			  "cloudCredentialsIDs": [
				"string"
			  ],
			  "sourceRegion": "string",
			  "licensesIDs": [
				"string"
			  ],
			  "replicationReversed": true,
			  "replicationConfiguration": "string",
			  "type": "MIGRATION",
			  "id": "string",
			  "features": {
				"awsExtendedHddTypes": true,
				"pit": true,
				"enableVolumeEncryption": true,
				"drTier2": true
			  }
			}
		
		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
	#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		
		[Parameter(ParameterSetName = "Config", Position = 0, ValueFromPipeline = $true, Mandatory = $true)]
		[System.Collections.Hashtable]$Config = @{},

		[Parameter(ParameterSetName = "Individual")]
		[System.String]$Name,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateLength(1, 1)]
		[System.Guid[]]$CloudCredentialsIDs = @(),

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	DynamicParam {

		# Create the dictionary 
		$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		if ($Config -eq $null -or $Config -eq @{})
		{
			if (-not [System.String]::IsNullOrEmpty($Session)) {
				$DynSessionInfo = $script:Sessions.Get_Item($Session)
				$DynSession = $Session
			}
			else {
				$DynSessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
				$DynSession = $DynSessionInfo.User.Username
			}

			$DynSplat = @{
				"Session" = $DynSession
			}

			if ($ProjectId -ne $null -and $ProjectId -ne [System.Guid]::Empty)
			{
				$DynSplat.Add("ProjectId", $ProjectId)
			}

			New-DynamicParameter -Name "Source" -Type ([System.String]) -Mandatory -ValidateSet ((Get-CECloudRegion @DynSplat | Select-Object -ExpandProperty Name) + "Generic") -ParameterSets @("Individual") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			New-DynamicParameter -Name "Target" -Type ([System.String]) -Mandatory -ValidateSet ($script:CloudIds.Keys) -ParameterSets @("Individual") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			New-DynamicParameter -Name "ReplicationConfiguration" -Type ([System.Guid]) -Mandatory -ValidateSet(Get-CEReplicationConfiguration @DynSplat | Select-Object -ExpandProperty Id) -ParameterSets @("Individual") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
		}

		return $RuntimeParameterDictionary
	}

	Begin {

	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3)
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			# If a config hashtable wasn't provided, build one for the parameter set being used
			if ($PSCmdlet.ParameterSetName -ne "Config")
			{
				[System.Collections.Hashtable]$SessSplat = @{
					"Session" = $Session
				}

				if ($ProjectId -ne [System.Guid]::Empty)
				{
					$SessSplat.Add("ProjectId", $ProjectId)
				}

				[PSCustomObject[]]$CERegions = Get-CECloudRegion @SessSplat 

				# Convert only the non-common parameters specified into a hashtable
				$Params = @{}

				foreach ($Item in (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key) })
                {
					[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
                    $Params.Add($Item.Key, $Sets)
                }

                $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
                    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

                    if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                    {
						[System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
						$Params.Add($Param.Name, $ParameterSets)
                    }
                }

				$Config = @{}

				# Get the parameters for the command
				foreach ($Item in $Params.GetEnumerator())
				{
					# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
					if ($Item.Value.Contains($PSCmdlet.ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
					{
						# Check to see if it was supplied by the user
						if ($PSBoundParameters.ContainsKey($Item.Key))
						{
							# If it was, add it to the config object
							if ($Item.Key -ieq "Source")
							{
								$SourceId = (($CERegions | Select-Object Name,Id) + [PSCustomObject]@{"Name" = "Generic"; "Id" = $script:CloudIds["Generic"]}) | Where-Object {$_.Name -ieq $PSBoundParameters[$Item.Key]} | Select-Object -First 1 -ExpandProperty Id
								$Config.Add("sourceRegion", $SourceId)
							}
							elseif ($Item.Key -ieq "Target")
							{
								$Config.Add("targetCloudId", $script:CloudIds[$Item.Value])
							}
							else 
							{
								$Config.Add($Item.Key, $PSBoundParameters[$Item.Key])
							}
						}
					}
				}
			}

			if ($Config -ne $null -and $Config -ne @{} -and $Config.Count -gt 0)
			{		
				if (-not $Config.ContainsKey("CloudCredentialsIDs"))
				{
					$Config.Add("CloudCredentialsIDs", $Session.DefaultCloudCredentials)
				}

				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri "$($Session.Url)/projects" -Method Post -Body (ConvertTo-Json -InputObject $Config) -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				switch ($StatusCode)
				{
					201 {
						if ($PassThru) 
						{
							Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
						}

						break
					}
					400 {
						throw "Max projects per Account reached.`r`n$($Result.Content)"
					}
					409 {
						throw "Cannot be completed due to conflict.`r`n$($Result.Content)"
					}
					default {
						throw "There was an issue creating the project: $StatusCode $Reason - $($Result.Content)"
					}
				}
			}
			else
			{
				throw "The provided config did not contain any values with which to create the new project."
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {

	}
}

Function Get-CEProject {
	<#
        .SYNOPSIS
			Gets basic information about the CE project.

        .DESCRIPTION
			The cmdlet retrieves basic information about the CE project in the CE account.

		.PARAMETER Id
			The Id of the project to retrieve.

		.PARAMETER Current
			Specified that information about the current project retrieved from the loging should be returned.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CEProject

            Retrieves all projects up to 1500.

		.EXAMPLE
			Get-CEProject -Current
			
			Retrieves data about the current project.

        .INPUTS
            None or System.Guid

        .OUTPUTS
           System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			This is a JSON representation of the returned array:
			[
				{
				  "targetCloudId": "string",
				  "agentInstallationToken": "string",
				  "name": "string",
				  "usersIDs": [
					"string"
				  ],
				  "type": "MIGRATION",
				  "replicationReversed": true,
				  "sourceCloudCredentialsId": "string",
				  "cloudCredentialsIDs": [
					"string"
				  ],
				  "sourceRegion": "string",
				  "licensesIDs": [
					"string"
				  ],
				  "ceAdminProperties": {
					"comments": "string",
					"history": "string"
				  },
				  "replicationConfiguration": "string",
				  "sourceCloudId": "string",
				  "id": "string",
				  "features": {
					"awsExtendedHddTypes": true,
					"allowRecoveryPlans": true,
					"allowArchiving": true,
					"isDemo": true,
					"drTier2": true,
					"allowByolOnDedicatedInstance": true,
					"pit": true
				  }
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/16/2019
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
    [OutputType([PSCustomObject], [PSCustomObject[]])]
    Param(
		[Parameter(ParameterSetName = "Current")]
		[Switch]$Current,

		[Parameter(ValueFromPipeline = $true, Mandatory = "true", Position = 0, ParameterSetName = "Get")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		[System.String]$Path = "/projects"

		switch ($PSCmdlet.ParameterSetName)
		{
			"Get" {
				$Path += "/$($Id.ToString())"

				break
			}
			"List" {
				if ($Offset -gt 0 -or $Limit -lt 1500)
				{
					$QueryString = [System.String]::Empty

					if ($Offset -gt 0)
					{
						$QueryString += "&offset=$Offset"
					}

					if ($Limit -lt 1500)
					{
						$QueryString += "&limit=$Limit"
					}

					# Remove the first character which is an unecessary ampersand
					$Path += "?$($QueryString.Substring(1))"
				}
				break
			}
			"Current" {
				$Path += "/$($SessionInfo["DefaultProjectId"])"
				break
			}
			default {
				Write-Warning -Message "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
				break
			}
		}
		
		try {
			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
		}
		catch [Exception] {
			throw "There was an issue retrieving the project information: $($_.Exception.Message)"
		}

		if ($PSCmdlet.ParameterSetName -ieq "List")
		{
			Write-Output -InputObject $Result.Items			
		}
		else 
		{
			Write-Output -InputObject $Result
		}
    }

    End {
    }
}

Function Set-CEProject {
	<#
		.SYNOPSIS
			Configure project's source location, replication settings, etc.

		.DESCRIPTION
			Configure project's source location, replication settings, etc.

		.PARAMETER ProjectId
			The Id of the project to set. If this is not specified, the current project is used.

		.PARAMETER Config
			The config to update the project's settings.

			{
			  "targetCloudId": "string",
			  "name": "string",
			  "cloudCredentialsIDs": [
				"string"
			  ],
			  "sourceRegion": "string",
			  "replicationConfiguration": "string"
			}

		.PARAMETER Target
			The Name of the target cloud environment to use.

		.PARAMETER Name
			The name of the project.

		.PARAMETER CloudCredentialsIDs
			An array of 1 cloud credentials to use. This defaults to the current session.
		
		.PARAMETER ReplicationConfiguration
			The Id of the replication configuration for the project to use.

		.PARAMETER Source
			The Name of the source cloud environment to use.

		.PARAMETER PassThru
			If specified, the updated configuration is returned to the pipeline.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Set-CEProject -Source "Generic"

			Sets the current project to use the source replication environment as "Generic".

		.EXAMPLE
			Set-CEProject -Source "Generic" -Target "AWS" -Name "MyAWSMigration"

			Updates the current project to use a generic source (i.e on-premises), a destination of AWS, and names the project MyAWSMigration.

		.INPUTS
			None or System.Collections.Hashtable

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject

			The JSON representation of the returned object:
			{
			  "source": "string",
			  "replicationConfiguration": "string",
			  "id": "string",
			  "name": "string",
			  "type": "MIGRATION"
			}
		
		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "Config", Position = 0, ValueFromPipeline = $true, Mandatory = $true)]
		[System.Collections.Hashtable]$Config = @{},

		[Parameter(ParameterSetName = "Individual")]
		[System.String]$Name,

		[Parameter(ParameterSetName = "Individual")]
		[System.String]$Target,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateLength(1, 1)]
		[System.Guid[]]$CloudCredentialsIDs = @(),

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	DynamicParam {

		# Create the dictionary 
		$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		if ($Config -eq $null -or $Config -eq @{})
		{
			if (-not [System.String]::IsNullOrEmpty($Session)) {
				$DynSessionInfo = $script:Sessions.Get_Item($Session)
				$DynSession = $Session
			}
			else {
				$DynSessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
				$DynSession = $DynSessionInfo.User.Username
			}

			$DynSplat = @{
				"Session" = $DynSession
			}

			if ($ProjectId -ne $null -and $ProjectId -ne [System.Guid]::Empty)
			{
				$DynSplat.Add("ProjectId", $ProjectId)
			}

			New-DynamicParameter -Name "Source" -Type ([System.String]) -ValidateSet ((Get-CECloudRegion @DynSplat | Select-Object -ExpandProperty Name) + "Generic") -ParameterSets @("Individual") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			New-DynamicParameter -Name "Target" -Type ([System.String]) -ValidateSet ($script:CloudIds.Keys) -ParameterSets @("Individual") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
			New-DynamicParameter -Name "ReplicationConfiguration" -Type ([System.Guid]) -Mandatory -ValidateSet(Get-CEReplicationConfiguration @DynSplat | Select-Object -ExpandProperty Id) -ParameterSets @("Individual") -RuntimeParameterDictionary $RuntimeParameterDictionary | Out-Null
		}

		return $RuntimeParameterDictionary
	}

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			[System.Collections.Hashtable]$SessSplat = @{
				"Session" = $Session
			}

			if ($ProjectId -ne [System.Guid]::Empty)
			{
				$SessSplat.Add("ProjectId", $ProjectId)
			}

			[PSCustomObject[]]$CERegions = Get-CECloudRegion @SessSplat 

			# If a config hashtable wasn't provided, build one for the parameter set being used
			if ($PSCmdlet.ParameterSetName -ne "Config")
			{
				# Convert only the non-common parameters specified into a hashtable
				$Params = @{}

				foreach ($Item in (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key) })
                {
					[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
                    $Params.Add($Item.Key, $Sets)
                }

                $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
                    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

                    if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                    {
						[System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
						$Params.Add($Param.Name, $ParameterSets)
                    }
                }

				$Config = @{}

				# Get the parameters for the command
				foreach ($Item in $Params.GetEnumerator())
				{
					# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
					if ($Item.Value.Contains($PSCmdlet.ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
					{
						# Check to see if it was supplied by the user
						if ($PSBoundParameters.ContainsKey($Item.Key))
						{
							# If it was, add it to the config object
							if ($Item.Key -ieq "Source")
							{
								$SourceId = (($CERegions | Select-Object Name,Id) + [PSCustomObject]@{"Name" = "Generic"; "Id" = $script:CloudIds["Generic"]}) | Where-Object {$_.Name -ieq $PSBoundParameters[$Item.Key]} | Select-Object -First 1 -ExpandProperty Id
								$Config.Add("sourceRegion", $SourceId)
							}
							elseif ($Item.Key -ieq "Target")
							{
								$Config.Add("targetCloudId", $script:CloudIds[$Item.Value])
							}
							else 
							{
								$Config.Add($Item.Key, $PSBoundParameters[$Item.Key])
							}
						}
					}
				}
			}

			if ($Config -ne $null -and $Config -ne @{} -and $Config.Count -gt 0)
			{		
				if (-not $Config.ContainsKey("CloudCredentialsIDs"))
				{
					$Config.Add("CloudCredentialsIDs", $Session.DefaultCloudCredentials)
				}

				# We need the project to see the original source
				[System.Collections.Hashtable]$CurrentProject = Get-CEProject @SessSplat | ConvertTo-Hashtable

				# Build the confirmation messages with warnings about updates to source and destination
				$ConfirmMessage = "The action you are about to perform is destructive!"

				if (-not [System.String]::IsNullOrEmpty($Config["source"]))
				{        
					$OriginalSrc = $CurrentProject["source"]
					$OriginalSource = ($CERegions + [PSCustomObject]@{"Name" = "Generic"; "Id" = $script:CloudIds["Generic"]} ) | Where-Object {$_.Id -ieq $OriginalSrc } | Select-Object -First 1 -ExpandProperty Name
                    
					$ConfirmMessage += "`r`n`r`nChanging your Live Migration Source from $OriginalSource to $($PSBoundParameters["Source"]) will cause all current instances to be disconnected from CloudEndure: you will need to reinstall the CloudEndure Agent on all the instances and data replication will restart from zero."
				}

				if (-not [System.String]::IsNullOrEmpty($Config["replicationConfiguration"]))
				{
					$ConfirmMessage += "`r`n`r`nChanging your Live Migration Target replication configuration will cause all current instances to be disconnected from CloudEndure: you will need to reinstall the CloudEndure Agent on all the instances and data replication will restart from zero."
				}

				$WhatIfDescription = "Updated project configuration to $(ConvertTo-Json -InputObject $Config)"
				$ConfirmCaption = "Update Project Configuration"

				if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
				{
					if ($ProjectId -eq [System.Guid]::Empty)
					{
						$ProjectId = $SessionInfo.ProjectId
					}

					[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId"

					Write-Verbose -Message "Sending updated config`r`n$(ConvertTo-Json -InputObject $Config)"
					
					$StatusCode = 0
					$Reason = ""

					try {
						[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Patch -Body (ConvertTo-Json -InputObject $Config) -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
						$StatusCode = $Result.StatusCode
						$Reason = $Result.StatusDescription
					}
					catch [System.Net.WebException] {
						[System.Net.WebException]$Ex = $_.Exception

						if ($Ex.Response -eq $null)
						{
							$Reason = "$($Ex.Status): $($Ex.Message)"
							$StatusCode = 500
						}
						else
						{
							[System.Net.HttpWebResponse]$Response = $Ex.Response
							$StatusCode = [System.Int32]$Response.StatusCode
			
							[System.IO.Stream]$Stream = $Response.GetResponseStream()
							[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
							[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
							$Content = $Reader.ReadToEnd()

							$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
						}
					}
					catch [Exception]  {
						$Reason = $_.Exception.Message
					}

					if ($StatusCode -eq 200)
					{
						if ($PassThru) 
						{
							Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
						}
					}
					else
					{
						throw "There was an issue updating the project configuration: $StatusCode $Reason - $($Result.Content)"
					}
				}
			}
			else
			{
				Write-Warning -Message "No updated configuration properties specified."
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Remove-CEProject {
	<#
		.SYNOPSIS
			Deletes a project and all sub-resources including cloud assets other than launched target machines.

		.DESCRIPTION
			Deletes a project and all sub-resources including cloud assets other than launched target machines.

		.PARAMETER ProjectId
			The Id of the project to delete.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Remove-CEProject -ProjectId 0cd58880-2ba0-469c-95f6-ed851f034145

			Deletes the specified project.

		.INPUTS
			None or System.Guid

		.OUTPUTS
			None 
		
		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {

	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3)
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			# Build the confirmation messages with warnings about updates to source and destination
			$ConfirmMessage = @"
The action you are about to perform is destructive!"

All sub-resources including cloud assets other than currently launched target machines will be deleted.
"@

			$WhatIfDescription = "Deleted project $ProjectId"
			$ConfirmCaption = "Delete Project"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId"

				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Delete -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -ne 204)
				{
					throw "There was an issue deleting the project $ProjectId`: $StatusCode $Reason - $($Result.Content)"
				}
				else
				{
					Write-Verbose -Message "Project successfully deleted."
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

#endregion

#region Cloud Credentials

Function New-CECloudCredential {
	<#
		.SYNOPSIS
			Provide the credentials with which to access the cloud API.

		.DESCRIPTION
			Provide the credentials with which to access the cloud API.

		.PARAMETER Credential
			The credential conifguration to create.

			The configuration schema is as follows:
			{
			  "publicKey": "string",
			  "name": "string",
			  "cloudId": "string",
			  "privateKey": "string",
			  "accountIdentifier": "string"
			}

		.PARAMETER PublicKey
			AWS Only. The public part of the Cloud credentials.

		.PARAMETER Name
			An optional (can be empty), user provided, descriptive name.

		.PARAMETER CloudId
			The GUID Id of the cloud to create the credentials for.

		.PARAMETER PrivateKey,
			Cloud credentials secret. For AWS - The secret access key, For GCP - The private key in JSON format, For Azure - The certificate file.

		.PARAMETER AccountIdentifier.
			Azure & GCP Only. Cloud account identifier. For GCP - The project ID, For Azure - The subscription ID.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			If specified, the new cloud credential configuration is passed to the pipeline.

		.EXAMPLE
			New-CECloudCredential -PublicKey AKIA12341234 -CloudId AWS -PrivateKey asdfghhoitreq+ -Name "MyAWSCreds"

			Creates new AWS credentials for CE to use.

		.INPUTS
			None or System.Collections.Hashtable

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject
			
		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
	#>
	[CmdletBinding()]
	[OutputType()]
	Param(
		[Parameter(ParameterSetName = "Credential", ValueFromPipeline = $true, Position = 0)]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$Credential,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateNotNullOrEmpty()]
		[System.String]$PublicKey,

		[Parameter(ParameterSetName = "Individual")]
		[System.String]$Name,

		[Parameter(Mandatory = $true, ParameterSetName = "Individual")]
		[ValidateSet("AWS", "Azure", "GCP", "On-Premises")]
		[System.String]$CloudId,

		[Parameter(Mandatory = $true, ParameterSetName = "Individual")]
		[ValidateNotNullOrEmpty()]
		[System.String]$PrivateKey,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateNotNullOrEmpty()]
		[System.String]$AccountIdentifier,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		 $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($PSCmdlet.ParameterSetName -ne "Credential")
			{
				# Convert only the non-common parameters specified into a hashtable
				$Params = @{}

				foreach ($Item in (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key)})
                {
					[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
                    $Params.Add($Item.Key, $Sets)
                }

                $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
                    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

                    if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                    {
						[System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
						$Params.Add($Param.Name, $ParameterSets)
                    }
                }

				$Credential = @{}

				# Get the parameters for the command
				foreach ($Item in $Params.GetEnumerator())
				{
					# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
					if ($Item.Value.Contains($PSCmdlet.ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
					{
						# Check to see if it was supplied by the user
						if ($PSBoundParameters.ContainsKey($Item.Key))
						{
							# If it was, add it to the credential object

							if ($Item.Key -ieq "CloudId")
							{
								$Credential.Add("cloudId", $script:CloudIds[$PSBoundParameters[$Item.Key]])
							}
							elseif ($Item.Key -ieq "PrivateKey")
							{
								$Credential.Add("privateKey", $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PSBoundParameters[$Item.Key]))))
							}
							else
							{
								$Credential.Add($Item.Key.Substring(0, 1).ToLower() + $Item.Key.Substring(1), $PSBoundParameters[$Item.Key])
							}
						}
					}
				}
			}

			[System.String]$Uri = "$($SessionInfo.Url)/cloudCredentials"
			
			Write-Verbose -Message "New CE CloudCredentials:`r`n$(ConvertTo-Json -InputObject $Credential)"
			
			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -Body (ConvertTo-Json -InputObject $Credential) -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}

			if ($StatusCode -eq 201)
			{
				if ($PassThru)
				{
					Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
				}
			}
			else
			{
				throw "There was an issue creating the new cloud credentials: $StatusCode $Reason - $($Result.Content)"
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Set-CECloudCredential {
	<#
		.SYNOPSIS
			Updates cloud credentials for CE to use in the target environment.

		.DESCRIPTION
			This cmdlet updates credentials that CloudEndure will utilize to launch resources in the target environment.

		.PARAMETER Credential
			The credential conifguration to create.

			The configuration schema is as follows:
			{
			  "publicKey": "string",
			  "name": "string",
			  "cloudId": "string",
			  "privateKey": "string",
			  "accountIdentifier": "string"
			}

		.PARAMETER PublicKey
			AWS Only. The public part of the Cloud credentials.

		.PARAMETER Name
			An optional (can be empty), user provided, descriptive name.

		.PARAMETER CloudId
			The GUID Id of the cloud to create the credentials for. If this is not specified, the current cloud is used.

		.PARAMETER PrivateKey,
			Cloud credentials secret. For AWS - The secret access key, For GCP - The private key in JSON format, For Azure - The certificate file.

		.PARAMETER AccountIdentifier.
			Azure & GCP Only. Cloud account identifier. For GCP - The project ID, For Azure - The subscription ID.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			If specified, the updated cloud credential configuration is passed to the pipeline.

		.EXAMPLE 
			Set-CECloudCredential -PublicKey AKIAPUTJUST34HYMMDRE -PrivateKey g3t89hLRcAhhq67KB8LNdx2C+9twO49uvajFF1Wa -Name "UpdatedAWSCreds"

			This sets new credentials for the current CE account.

		.INPUTS
			None

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject

			The JSON representation of the returned object:
			{
			  "id": "string",
			  "publicKey": "string",
			  "accountIdentifier": "string",
			  "cloud": "string",
			  "name": "string"
			}
			
		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([PSCustomObject])]
	Param(
		# This Id can be an empty GUID for on-premises
		[Parameter()]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "Credential", ValueFromPipeline = $true, Position = 0)]
		[ValidateNotNull()]
		[System.Collections.Hashtable]$Credential,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateNotNullOrEmpty()]
		[System.String]$PublicKey,

		[Parameter(ParameterSetName = "Individual")]
		[System.String]$Name,

		[Parameter(ParameterSetName = "Individual", Mandatory = $true)]
		[ValidateSet("AWS", "Azure", "GCP", "On-Premises")]
		[System.String]$CloudId,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateNotNullOrEmpty()]
		[System.String]$PrivateKey,

		[Parameter(ParameterSetName = "Individual")]
		[ValidateNotNullOrEmpty()]
		[System.String]$AccountIdentifier,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty,

		[Parameter()]
		[Switch]$Force
	)

	Begin {
	}

	Process {
		if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
            $Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if (-not $PSBoundParameters.ContainsKey("Id"))
			{
				$Id = $SessionInfo.DefaultCloudCredentials
			}

			[System.String]$Uri = "$($SessionInfo.Url)/cloudCredentials/$Id"

			if ($PSCmdlet.ParameterSetName -ine "Credential")
			{
				# Convert only the non-common parameters specified into a hashtable
				$Params = @{}

				foreach ($Item in (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key)})
                {
					[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
                    $Params.Add($Item.Key, $Sets)
                }

                $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
                    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

                    if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                    {
						[System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
						$Params.Add($Param.Name, $ParameterSets)
                    }
                }

				$Credential = @{}

				# Get the parameters for the command
				foreach ($Item in $Params.GetEnumerator())
				{
					# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
					if ($Item.Value.Contains($PSCmdlet.ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
					{
						# Check to see if it was supplied by the user
						if ($PSBoundParameters.ContainsKey($Item.Key))
						{
							# If it was, add it to the credential object

							if ($Item.Key -ieq "CloudId")
							{
								$Credential.Add("cloudId", $script:CloudIds[$PSBoundParameters[$Item.Key]])
							}
							elseif ($Item.Key -ieq "PrivateKey")
							{
								$Credential.Add("privateKey", $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($PSBoundParameters[$Item.Key]))))
							}
							else
							{
								$Credential.Add($Item.Key.Substring(0, 1).ToLower() + $Item.Key.Substring(1), $PSBoundParameters[$Item.Key])
							}
						}
					}
				}
			}

			if (-not $Credential.ContainsKey("cloudId"))
			{
				[System.Collections.Hashtable]$SessSplat = @{
					"Session" = $Session
				}

				$CurrentCreds = Get-CECloudCredential -Current @SessSplat
				$Credential.Add("cloudId", $CurrentCreds.Cloud)
			}

			$ConfirmMessage = "Are you sure you want to update the cloud credentials?"
			$WhatIfDescription = "Updated credentials."
			$ConfirmCaption = "Update CE Credentials"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Sending updated config:`r`n $(ConvertTo-Json -InputObject $Credential)"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Patch -Body (ConvertTo-Json -InputObject $Credential) -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 200)
				{
					Write-Verbose -Message "Successfully updated cloud credentials."

					if ($PassThru)
					{
						Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
					}
				}
				else
				{
					throw "There was an issue updating the cloud credentials: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Get-CECloudCredential {
	<#
        .SYNOPSIS
			Returns information about cloudCredentials in the account.

        .DESCRIPTION
            This cmdlet returns information about cloudCredentials in the account. If an Id is specified, the information specific to that Id is returned, otherwise the credentials are listed.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CECloudCredential -Current

            Retrieves the cloud credentials associated with the current account.

		.EXAMPLE 
			Get-CECloudCredential -Id 9f620e77-3f2e-4df3-bc37-ec4ee736d92f

			Get the cloud credential associated with the provided Id.

		.EXAMPLE
			Get-CECloudCredential -Limit 10
		
			Retrieves the first 10 cloud credentials in the current account.

        .INPUTS
            None or System.Guid

        .OUTPUTS
           System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
    [OutputType([System.Management.Automation.PSCustomObject], [System.Management.Automation.PSCustomObject[]])]
    Param(
		# This parameter can be specified as the empty GUID for on-premises
		[Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0, ParameterSetName = "Get")]
		[System.Guid]$Id,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter(ParameterSetName = "Current")]
		[Switch]$Current,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			[System.String]$Uri = "$($SessionInfo.Url)/cloudCredentials"

			switch ($PSCmdlet.ParameterSetName)
			{
				"Get" {
					$Uri += "/$($Id.ToString())"

					break
				}
				"Current" {
					$Id = $SessionInfo.DefaultCloudCredentials
					$Uri += "/$($Id.ToString())"

					break
				}
				"List" {
					if ($Offset -gt 0 -or $Limit -lt 1500)
					{
						$QueryString = [System.String]::Empty

						if ($Offset -gt 0)
						{
							$QueryString += "&offset=$Offset"
						}

						if ($Limit -lt 1500)
						{
							$QueryString += "&limit=$Limit"
						}

						# Remove the first character which is an unecessary ampersand
						$Uri += "?$($QueryString.Substring(1))"
					}
					break
				}
				default {
					Write-Warning -Message "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
					break
				}
			}

			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Get -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}
        
			if ($StatusCode -eq 200)
			{
				if ($PSCmdlet.ParameterSetName -ieq "List")
				{
					Write-Output -InputObject ([PSCustomObject[]](ConvertFrom-Json -InputObject $Result.Content).Items)
				}
				else
				{
					Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
				}
			}
			else
			{
				throw "There was an issue getting the cloud credentials: $StatusCode $Reason - $($Result.Content)"
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

#endregion

#region Cloud

Function Get-CECloud {
	<#
		.SYNOPSIS
			Gets information about the available clouds to use with CloudEndure

        .DESCRIPTION
			The cmdlet retrieves information about a cloud or lists the available clouds if no Id is specified.

		.PARAMETER Id
			The Id of the cloud to retrieve. If no Id is specified, all available clouds are returned.

		.PARAMETER Name
			The name of the cloud to retrieve. If no name is specified, all available clouds are returned.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Get-CECloud

			Retrieves all of the available clouds.

		.EXAMPLE
			Get-CECloud -Id 4c7b3582-9e73-4866-858a-8e1ac6e818b3

			Retrieves information about the cloud with the specified Id, which is AWS.

		.EXAMPLE
			Get-CECloud -Name AWS

			Retrieves information about the AWS cloud.

		.INPUTS
			None

		.OUPUTS
			System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			This is a JSON representation of the return array:
			[
				{
				  "id": "string",
				  "roles": [
					"SOURCE"
				  ],
				  "name": "AWS"
				}
			]
			
		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/16/2019
	#>
	[CmdletBinding(DefaultParameterSetName = "List")]
	[OutputType([System.Management.Automation.PSCustomObject], [System.Management.Automation.PSCustomObject[]])]
	Param (
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "GetById")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "GetByName")]
		[ValidateNotNullOrEmpty()]
		[System.String]$Name = [System.String]::Empty,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		[System.String]$Path = "/clouds"
		[System.Int32]$ResultCount = 0
		[System.Boolean]$Found = $false

		do {
			[System.String]$QueryString = "?offset=$Offset&limit=$Limit"
			[System.String]$TempUri = "$Path$QueryString"

			Write-Verbose -Message "Querying clouds from $Offset to $($Offset + $Limit)."

			try {
				$Result = Invoke-CERequest -Path $TempUri -Method Get -Session $Session -ExpectedResponseCode 200
			}
			catch [Exception] {
				throw "There was an issue listing the clouds: $($_.Exception.Message)"
			}

			[PSCustomObject[]]$Content = $Result.Items
			$ResultCount = $Result.Items.Length

			switch -wildcard ($PSCmdlet.ParameterSetName)
			{
				"Get*" {

					$Filter = {}
					if ($PSCmdlet.ParameterSetName -eq "GetById")
					{
						$Filter = {$_.Id -ieq $Id.ToString()}
					}
					else
					{
						$Filter = {$_.name -ieq $Name}
					}

					$Cloud = $Content | Where-Object $Filter

					if ($Cloud -ne $null)
					{
						Write-Output -InputObject ([PSCustomObject]($Cloud | Select-Object -First 1))
						$Found = $true
						break
					}
					else
					{
						$Offset += $Limit
					}

					break
				}
				"List" {
					Write-Output -InputObject $Content
					$ResultCount = $Limit - 1 # Make sure we break the do loop
					break
				}
				default {
					throw "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
				}
			}

		} while ($ResultCount -ge $Limit)

		if ($PSCmdlet.ParameterSetName -like "Get*" -and -not $Found)
		{
			throw "The cloud with Id $Id was not found."
		}
	}

	End {
	}
}

Function Get-CECloudRegion {
	<#
        .SYNOPSIS
			Gets information about the available destination cloud regions.

        .DESCRIPTION
			The cmdlet retrieves information about a region in the target cloud or if no Id is specified, all available regions in the target cloud. 
			This information includes the available regions, their subnets, security groups, IAM instance profiles, available instance types, and KMS keys.

		.PARAMETER Id
			The Id of the region to retrieve. If no Id is specified, all available regions in the target cloud are returned.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

		.PARAMETER Current
			Gets the region information about a project's target region. This defaults to the default project.

		.PARAMETER Target
			Gets the region information about a project's target region. This defaults to the default project.

		.PARAMETER CloudCredentials
			UUID of the credentials to use. In case of on-premise, you should use the null UUID "00000000-0000-0000-0000-000000000000". If this is not specified, it defaults to the cloud credentials acquired at logon.

		.PARAMETER ProjectId
			The project Id to use if you are trying to get access about a source or destination region. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CECloudRegion

            Retrieves the details of all regions the destination cloud environment.

		.EXAMPLE
			Get-CECloudRegion -Id 47d842b8-ebfa-4695-90f8-fb9ab686c708

			Retrieves details of the region identified with the supplied Guid.

		.EXAMPLE
			Get-CECloudRegion -Current
			
			Retrieves details about the current target region.

        .INPUTS
            System.Guid

        .OUTPUTS
           System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			This is a JSON representation of the output array:
			[		
				{
				  "subnets": [
					{
					  "subnetId": "string",
					  "networkId": "string",
					  "name": "string"
					}
				  ],
				  "placementGroups": [
					"string"
				  ],
				  "scsiAdapterTypes": [
					"string"
				  ],
				  "instanceTypes": [
					"string"
				  ],
				  "zones": [
					"string"
				  ],
				  "volumeEncryptionKeys": [
					"string"
				  ],
				  "cloud": "string",
				  "securityGroups": [
					{
					  "networkId": "string",
					  "securityGroupId": "string",
					  "name": "string"
					}
				  ],
				  "logicalLocations": [
					{
					  "locationId": "string",
					  "name": "string"
					}
				  ],
				  "staticIps": [
					"string"
				  ],
				  "maxCpusPerMachine": 0,
				  "networkInterfaces": [
					{
					  "subnetId": "string",
					  "name": "string",
					  "privateIp": "string"
					}
				  ],
				  "computeLocations": [
					{
					  "isEncryptionSupported": true,
					  "locationId": "string",
					  "name": "string"
					}
				  ],
				  "name": "string",
				  "storageLocations": [
					{
					  "locationId": "string",
					  "name": "string"
					}
				  ],
				  "iamRoles": [
					"string"
				  ],
				  "id": "string",
				  "maxCoresPerMachineCpu": 0,
				  "dedicatedHosts": [
					"string"
				  ],
				  "networkAdapterTypes": [
					"string"
				  ],
				  "maxMbRamPerMachine": 0
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/16/2019
    #>
	[CmdletBinding(DefaultParameterSetName = "List")]
	[OutputType([PSCustomObject], [PSCustomObject[]])]
	Param(
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Get")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		<# TODO
		[Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0, ParameterSetName = "GetByName")]
		[ValidateNotNullOrEmpty()]
		[System.String]$Name = [System.String]::Empty,
		#>

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter(ParameterSetName = "GetTarget")]
		[Switch]$Target,

		[Parameter(ParameterSetName = "GetSource")]
		[Switch]$Source,

		[Parameter()]
		[System.Guid]$CloudCredentials = [System.Guid]::Empty,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {

	}

	Process {
		$SessionInfo = Get-CESessionOrDefault -Session $Session

		$Splat = @{}

		if (-not [System.String]::IsNullOrEmpty($Session))
		{
			$Splat.Add("Session", $Session)
		}

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo["DefaultProjectId"]
		}

		# Check to see if they were specified since an empty GUID means on-premises
		if (-not $PSBoundParameters.ContainsKey("CloudCredentials"))
		{
			$CloudCredentials = $SessionInfo["DefaultCloudCredentialsId"]
		}

		[System.String]$Path = "/cloudCredentials/$CloudCredentials/regions"

		switch ($PSCmdlet.ParameterSetName)
		{
			"Get" {
				$Path += "/$($Id.ToString())"

				break
			}
			"GetTarget" {	
				$Project = Get-CEProject -Id $ProjectId @Splat

				if ([System.String]::IsNullOrEmpty($Project.ReplicationConfiguration))
				{
					throw  "The project $($Project.Name) ($ProjectId) does not have a replication configuration yet, so the target region cannot be determined."
				}

				$ReplConfig = Get-CEReplicationConfiguration -Id $Project.ReplicationConfiguration -ProjectId $ProjectId @Splat
				$Path += "/$($ReplConfig.Region.ToString())"

				break
			}
			"GetSource" {
				$Project = Get-CEProject -Id $ProjectId @Splat
				$Id = $Project.sourceRegion
				
				if ($Id -ne $script:CloudIds["Generic"])
				{
					$Path += "/$($Id.ToString())"
				}
				else 
				{
					return [PSCustomObject]@{
						"cloud" = "GENERIC"; 
						"iamRoles" = @(); 
						"id" = $script:CloudIds["Generic"]; 
						"instanceTypes" = @(); 
						"name" = "Generic"; 
						"placementGroups" = @(); 
						"securityGroups" = @(); 
						"staticIps" = @(); 
						"subnets" = @(@{"name" = "Default"}); 
						"volumeEncryptionKeys" = @("Default")
					}
				}

				break
			}
			"List" {
				if ($Offset -gt 0 -or $Limit -lt 1500)
				{
					$QueryString = [System.String]::Empty

					if ($Offset -gt 0)
					{
						$QueryString += "&offset=$Offset"
					}

					if ($Limit -lt 1500)
					{
						$QueryString += "&limit=$Limit"
					}

					# Remove the first character which is an unecessary ampersand
					$Path += "?$($QueryString.Substring(1))"
				}
				break
			}
			default {
				Write-Warning -Message "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
				break
			}
		}
		try {
			$Result = Invoke-CERequest -Path $Path -Method Get -Session $Session -ExpectedResponseCode 200
		
			if ($PSCmdlet.ParameterSetName -eq "List")
			{
				$Return += $Result.Items

				Write-Output -InputObject $Result.Items
			}
			else 
			{
				Write-Output -InputObject $Result
			}
		}
		catch [Exception] {
			throw "There was an issue listing the cloud regions: $($_.Exception.Message)"
		}
	}

	End {
	}
}

Function Get-CETargetCloudRegion {
	<#
        .SYNOPSIS
			Gets information about the destination cloud environment.

        .DESCRIPTION
			The cmdlet retrieves information about the target/destination cloud environment.

		.PARAMETER CloudCredentials
			UUID of the credentials to use. In case of on-premise, you should use the null UUID "00000000-0000-0000-0000-000000000000". If this is not specified, it defaults to the cloud credentials acquired at logon.

		.PARAMETER ProjectId
			The project Id of whose target cloud you want to retrieve. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CETargetCloud

            Retrieves the details of the destination cloud environment.

        .INPUTS
            None

        .OUTPUTS
           System.Management.Automation.PSCustomObject

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
    #>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	Param(
		[Parameter()]
		[System.Guid]$CloudCredentials = [System.Guid]::Empty,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {

	}

	Process {
		$Splat = @{}

		if (-not [System.String]::IsNullOrEmpty($Session))
		{
			$Splat.Add("Session", $Session)
		}

		if ($PSBoundParameters.ContainsKey("CloudCredentials"))
		{
			$Splat.Add("CloudCredentials", $CloudCredentials)
		}

		if ($PSBoundParameters.ContainsKey("ProjectId"))
		{
			$Splat.Add("ProjectId", $ProjectId)
		}

		Write-Output -InputObject (Get-CECloudRegion -Target @Splat)
	}

	End {
	}
}

Function Get-CESourceCloudRegion {
	<#
        .SYNOPSIS
			Gets information about the source cloud environment.

        .DESCRIPTION
			The cmdlet retrieves information about the source cloud environment.

		.PARAMETER CloudCredentials
			UUID of the credentials to use. In case of on-premise, you should use the null UUID "00000000-0000-0000-0000-000000000000". If this is not specified, it defaults to the cloud credentials acquired at logon.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CESourceCloud

            Retrieves the details of the source cloud environment.

        .INPUTS
            None

        .OUTPUTS
           System.Management.Automation.PSCustomObject

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
    #>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	Param(
		[Parameter()]
		[System.Guid]$CloudCredentials = [System.Guid]::Empty,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {

	}

	Process {
		$Splat = @{}

		if (-not [System.String]::IsNullOrEmpty($Session))
		{
			$Splat.Add("Session", $Session)
		}

		if ($PSBoundParameters.ContainsKey("CloudCredentials"))
		{
			$Splat.Add("CloudCredentials", $CloudCredentials)
		}

		if ($PSBoundParameters.ContainsKey("ProjectId"))
		{
			$Splat.Add("ProjectId", $ProjectId)
		}

		Write-Output -InputObject (Get-CECloudRegion -Source @Splat)
	}

	End {
	}
}

#endregion

#region Machines

Function Get-CEMachine {
     <#
        .SYNOPSIS
           Gets a list of CE machines in an account or a specific CE machine.

        .DESCRIPTION
            The cmdlet lists all of the CE machines in the account if no Id is provided. If an Id is provided, then that specific machine is fetched.

		.PARAMETER Id
			The Id of the instance to get. If this is not specified, all instances are returned.

		.PARAMETER Offset
			With which item to start (0 based).

		.PARAMETER Limit
			A number specifying how many entries to return between 0 and 1500 (defaults to 1500).

		.PARAMETER IgnoreMachineStatus
			Returns all machines in the project regardless of replications status.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CEMachine

            Lists all of the CE machines in the account.

		.EXAMPLE
			Get-CEMachine -Id 9f620e77-3f2e-4df3-bc37-ec4ee736d92f

			Gets details for the machine specified.

        .INPUTS
            None or System.Guid

        .OUTPUTS
           System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			This is a JSON representation of the returned array:
			[
				{
				  "sourceProperties": {
					"name": "string",
					"disks": [
					  {
						"isProtected": true,
						"name": "string",
						"size": 0
					  }
					],
					"machineCloudState": "string",
					"publicIps": [
					  "string"
					],
					"memory": 0,
					"os": "string",
					"cpu": [
					  {
						"cores": 0,
						"modelName": "string"
					  }
					],
					"machineCloudId": "string"
				  },
				  "replicationInfo": {
					"lastConsistencyDateTime": "2017-09-10T14:19:39Z",
					"nextConsistencyEstimatedDateTime": "2017-09-10T14:19:39Z",
					"rescannedStorageBytes": 0,
					"backloggedStorageBytes": 0,
					"initiationStates": {
					  "items": [
						{
						  "steps": [
							{
							  "status": "NOT_STARTED",
							  "message": "string",
							  "name": "WAITING_TO_INITIATE_REPLICATION"
							}
						  ],
						  "startDateTime": "2017-09-10T14:19:39Z"
						}
					  ],
					  "estimatedNextAttemptDateTime": "2017-09-10T14:19:39Z"
					},
					"replicatedStorageBytes": 0,
					"totalStorageBytes": 0
				  },
				  "license": {
					"startOfUseDateTime": "2017-09-10T14:19:39Z",
					"licenseId": "string"
				  },
				  "id": "string",
				  "replicationStatus": "STOPPED",
				  "replica": "string",
				  "lifeCycle": {
					"failoverDateTime": "2017-09-10T14:19:39Z",
					"cutoverDateTime": "2017-09-10T14:19:39Z",
					"lastTestDateTime": "2017-09-10T14:19:39Z",
					"connectionEstablishedDateTime": "2017-09-10T14:19:39Z",
					"agentInstallationDateTime": "2017-09-10T14:19:39Z"
				  },
				  "isAgentInstalled": true
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 9/11/2017
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
	[OutputType([PSCustomObject], [PSCustomObject[]])]
    Param(
        [Parameter(ValueFromPipeline = $true, Position = 0, ParameterSetName = "Get", Mandatory = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid]$Id = [System.Guid]::Empty,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, [System.UInt32]::MaxValue)]
		[System.UInt32]$Offset = 0,

		[Parameter(ParameterSetName = "List")]
		[ValidateRange(0, 1500)]
		[System.UInt32]$Limit = 1500,

		[Parameter(ParameterSetName = "List")]
		[Switch]$IgnoreMachineStatus,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/machines"

			switch ($PSCmdlet.ParameterSetName)
			{
				"Get" {
					$Uri += "/$($Id.ToString())"

					break
				}
				"List" {
					if ($Offset -gt 0 -or $Limit -lt 1500)
					{
						$QueryString = [System.String]::Empty

						if ($Offset -gt 0)
						{
							$QueryString += "&offset=$Offset"
						}

						if ($Limit -lt 1500)
						{
							$QueryString += "&limit=$Limit"
						}

						if ($IgnoreMachineStatus)
						{
							$QueryString += "&all=true"
						}

						# Remove the first character which is an unecessary ampersand
						$Uri += "?$($QueryString.Substring(1))"
					}
					break
				}
				default {
					Write-Warning -Message "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
					break
				}
			}

			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Get -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}
        
			if ($StatusCode -eq 200)
			{
				$Temp = ConvertFrom-Json -InputObject $Result.Content

				if ($PSCmdlet.ParameterSetName -ieq "List") 
				{
					Write-Output -InputObject $Temp.Items
				}
				else 
				{
					Write-Output -InputObject $Temp
				}
			}
			else
			{
				throw "There was an issue retrieving CE machines: $StatusCode $Reason - $($Result.Content)"
			}	
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Set-CEMachine {
	<#
		.SYNOPSIS
			Updates a machine's configuration.

		.DESCRIPTION
			This cmdlet updates a machine's configuration. It only accepts Launch time updates.

		.PARAMETER InstanceId
			The Id of the machine to update.

		.PARAMETER Config
			The configuration settings to update on the CE machine. This hashtable can include the following key values, but will only accept Launch time updates:

			{
			  "sourceProperties": {
				"name": "string",
				"disks": [
				  {
					"isProtected": true,
					"name": "string",
					"size": 0
				  }
				],
				"machineCloudState": "string",
				"publicIps": [
				  "string"
				],
				"memory": 0,
				"os": "string",
				"cpu": [
				  {
					"cores": 0,
					"modelName": "string"
				  }
				],
				"machineCloudId": "string"
			  },
			  "replicationInfo": {
				"lastConsistencyDateTime": "2017-10-04T15:34:44Z",
				"nextConsistencyEstimatedDateTime": "2017-10-04T15:34:44Z",
				"rescannedStorageBytes": 0,
				"backloggedStorageBytes": 0,
				"initiationStates": {
				  "items": [
					{
					  "steps": [
						{
						  "status": "NOT_STARTED",
						  "message": "string",
						  "name": "WAITING_TO_INITIATE_REPLICATION"
						}
					  ],
					  "startDateTime": "2017-10-04T15:34:44Z"
					}
				  ],
				  "estimatedNextAttemptDateTime": "2017-10-04T15:34:44Z"
				},
				"replicatedStorageBytes": 0,
				"totalStorageBytes": 0
			  },
			  "license": {
				"startOfUseDateTime": "2017-10-04T15:34:44Z",
				"licenseId": "string"
			  },
			  "id": "string",
			  "replicationStatus": "STOPPED",
			  "replica": "string",
			  "lifeCycle": {
				"lastTestLaunchDateTime": "2017-10-04T15:34:44Z",
				"connectionEstablishedDateTime": "2017-10-04T15:34:44Z",
				"agentInstallationDateTime": "2017-10-04T15:34:44Z",
				"lastCutoverDateTime": "2017-10-04T15:34:44Z",
				"lastRecoveryLaunchDateTime": "2017-10-04T15:34:44Z"
			  },
			  "isAgentInstalled": true
			}

		.PARAMETER LastTestLaunchDateTime
			The new last test launch datetime.

		.PARAMETER LastCutoverDateTime
			The new last cutover datetime.

		.PARAMETER LastRecoveryLaunchDateTime
			The new last recovery launch datetime.	

		.EXAMPLE
			Set-CEMachine -InstanceId 114b110e-12a3-48d4-b731-90ab3fccdf22 -LastTestLaunchDateTime (Get-Date)

		.INPUTS
			System.Guid

		.OUTPUTS
			None or PSCustomObject

			This is a JSON representation of the returned object:

			{
			  "sourceProperties": {
				"name": "string",
				"disks": [
				  {
					"isProtected": true,
					"name": "string",
					"size": 0
				  }
				],
				"machineCloudState": "string",
				"publicIps": [
				  "string"
				],
				"memory": 0,
				"os": "string",
				"cpu": [
				  {
					"cores": 0,
					"modelName": "string"
				  }
				],
				"machineCloudId": "string"
			  },
			  "replicationInfo": {
				"lastConsistencyDateTime": "2017-10-04T15:34:44Z",
				"nextConsistencyEstimatedDateTime": "2017-10-04T15:34:44Z",
				"rescannedStorageBytes": 0,
				"backloggedStorageBytes": 0,
				"initiationStates": {
				  "items": [
					{
					  "steps": [
						{
						  "status": "NOT_STARTED",
						  "message": "string",
						  "name": "WAITING_TO_INITIATE_REPLICATION"
						}
					  ],
					  "startDateTime": "2017-10-04T15:34:44Z"
					}
				  ],
				  "estimatedNextAttemptDateTime": "2017-10-04T15:34:44Z"
				},
				"replicatedStorageBytes": 0,
				"totalStorageBytes": 0
			  },
			  "license": {
				"startOfUseDateTime": "2017-10-04T15:34:44Z",
				"licenseId": "string"
			  },
			  "id": "string",
			  "replicationStatus": "STOPPED",
			  "replica": "string",
			  "lifeCycle": {
				"lastTestLaunchDateTime": "2017-10-04T15:34:44Z",
				"connectionEstablishedDateTime": "2017-10-04T15:34:44Z",
				"agentInstallationDateTime": "2017-10-04T15:34:44Z",
				"lastCutoverDateTime": "2017-10-04T15:34:44Z",
				"lastRecoveryLaunchDateTime": "2017-10-04T15:34:44Z"
			  },
			  "isAgentInstalled": true
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 12/11/2017
			
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[System.Guid]$InstanceId,

		[Parameter(Mandatory = $true, ParameterSetName = "Config")]
		[System.Collections.Hashtable]$Config = @{},

		[Parameter(ParameterSetName = "Property")]
		[ValidateNotNull()]
		[System.DateTime]$LastTestLaunchDateTime,

		[Parameter(ParameterSetName = "Property")]
		[ValidateNotNull()]
		[System.DateTime]$LastCutoverDateTime,

		[Parameter(ParameterSetName = "Property")]
		[ValidateNotNull()]
		[System.DateTime]$LastRecoveryLaunchDateTime,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {

	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3) 
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			if ($PSCmdlet.ParameterSetName -ne "Config")
			{
				# Convert only the non-common parameters specified into a hashtable
				$Params = @{}

				foreach ($Item in (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Key) -and -not @("InstanceId", "Config").Contains($_.Key)})
                {
					[System.String[]]$Sets = $Item.Value.ParameterSets.GetEnumerator() | Select-Object -ExpandProperty Key
                    $Params.Add($Item.Key, $Sets)
                }

                $RuntimeParameterDictionary.GetEnumerator() | Where-Object {-not $script:CommonParams.Contains($_.Name)} | ForEach-Object {
                    [System.Management.Automation.RuntimeDefinedParameter]$Param = $_.Value 

                    if ($Param.IsSet -and -not $Params.ContainsKey($Param.Name))
                    {
						[System.String[]]$ParameterSets = $Param.Attributes | Where-Object {$_ -is [System.Management.Automation.PARAMETERAttribute] } | Select-Object -ExpandProperty ParameterSetName
						$Params.Add($Param.Name, $ParameterSets)
                    }
                }

				$Config = @{"lifeCycle" = @{}}

				# Get the parameters for the command
				foreach ($Item in $Params.GetEnumerator())
				{
					# If the parameter is part of the Individual parameter set or is a parameter only part of __AllParameterSets
					if ($Item.Value.Contains($PSCmdlet.ParameterSetName) -or ($Item.Value.Length -eq 1 -and $Item.Value.Contains($script:AllParameterSets)))
					{
						# Check to see if it was supplied by the user
						if ($PSBoundParameters.ContainsKey($Item.Key))
						{
							# If it was, add it to the config object
							[System.DateTime]$Time = ([System.DateTime]$PSBoundParameters[$Item.Key])
							$Config["lifeCycle"].Add($Item.Key, $Time.ToString("yyyy-MM-ddTHH:mm:ssZ"))
						}
					}
				}
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/machines/$InstanceId"
			[System.String]$Body = ConvertTo-Json -InputObject $Config

			$ConfirmMessage = "Are you sure you want to update the CE machine configuration for machine $InstanceId`?"

			$WhatIfDescription = "Updated configuration to $Body"
			$ConfirmCaption = "Update CE Machine Configuration"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Sending updated machine config:`r`n$Body"

				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Patch -Body $Body -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 200)
				{
					if ($PassThru)
					{
						Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content)
					}
				}
				else
				{
					throw "There was an issue updating CE machine $InstanceId`: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {

	}
}

Function Remove-CEMachine {
	<#
        .SYNOPSIS
           Removes a machine from CloudEndure and initiates an uninstall of the agent on the source machine.

        .DESCRIPTION
            The cmdlet uninstalls the CloudEndure agent on the source instance, causes data replication to stop, and the instance will no longer appear in the CloudEndure Console.

			All cloud artifacts associated with those machines with the exception of launched target machines are deleted.

		.PARAMETER Ids
			The Ids of the instances to remove from CloudEndure.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Remove-CEMachine -Ids e0dc06ba-86b5-4c4c-b25b-20a68089c797 -Force

            Removes the CE instance with the specified Id and bypasses the confirm dialog.

		.EXAMPLE
            Remove-CEMachine -Ids @(e0dc06ba-86b5-4c4c-b25b-20a68089c797, b1df0696-8da5-4648-b2cc-222aa89c800) -Force

            Removes the CE instancea with the specified Ids and bypasses the confirm dialog.

        .INPUTS
            System.Guid[]

        .OUTPUTS
           None

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/21/2019
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	[OutputType()]
    Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Guid[]]$Ids = @(),

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
        $SessionInfo = Get-CESessionOrDefault -Session $Session

		if ($ProjectId -eq [System.Guid]::Empty)
		{
			$ProjectId = $SessionInfo.DefaultProjectId
		}

		[System.String]$Path = "/projects/$ProjectId/machines"

		[System.String]$Body = ConvertTo-Json -InputObject @{"machineIDs" = $Ids}

		$ConfirmMessage = @"
You are about to uninstall the CloudEndure Agent from $($Ids.Length) Source instance$(if ($Ids.Length -gt 1) { "s" }).

This will cause data replication to stop and the instance$(if ($Ids.Length -gt 1) { "s" }) will no longer appear in the CloudEndure Console.
"@

		$WhatIfDescription = "Deleted CE Instances $([System.String]::Join(",", $Ids))"
		$ConfirmCaption = "Delete CE Instance $([System.String]::Join(",", $Ids))"

		if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
		{
			try {
				$Result = Invoke-CERequest -Path $Path -Method Delete -Session $Session -Body $Body -ExpectedResponseCode 204
			}
			catch [Exception]
			{
				throw "There was an issue removing the CE machines: $($_.Exception.Message)"
			}		
		}	
    }

    End {
    }
}

Function Get-CEMachineReplica {
	<#
		.SYNOPSIS
			Gets a target machine details.

		.DESCRIPTION
			This cmdlet retrieves information about a target replica instance. If the id is not found, a 404 response is returned.

		.PARAMETER Id
			The Id of the replica instance to get.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Get-CEMachineReplica -Id cc7ba582-9e83-4866-858a-8e1ac6e818b4

			Gets the replica instance specified by the provided Id.

		.INPUTS
			System.Guid

		.OUPUTS
			System.Management.Automation.PSCustomObject

			This is a JSON representation of the return value:
			{
			  "machine": "string",
			  "cloudEndureCreationDateTime": "2017-09-10T14:19:39Z",
			  "name": "string",
			  "pointInTime": "string",
			  "machineCloudState": "string",
			  "publicIps": [
				"string"
			  ],
			  "regionId": "string",
			  "id": "string",
			  "machineCloudId": "string"
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(		
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid]$Id,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,
		
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/replicas/$($Id.ToString())"
			
			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Get -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}

			switch ($StatusCode)
			{
				200 {
					Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content)
					break
				}
				404 {
					throw "Replica Id $Id not found."
				}
				default{
					throw "There was an issue getting the replica instance data: $($Result.StatusCode) $($Result.StatusDescription) - $($Result.Content)"
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

#endregion

#region Actions

Function New-CEInstallationToken {
	<#
        .SYNOPSIS
			Replaces the current installation token with a new one.

        .DESCRIPTION
			The cmdlet creates a new installation token and invalidates the old one.

		.PARAMETER PassThru
			If specified, the new installation token will be returned to the pipeline.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            $Token = New-CEInstallationToken -PassThru

            Invalidates the old installation token and creates a new one, which is passed back to the pipeline.

        .INPUTS
            None

        .OUTPUTS
           None or System.String

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/8/2017
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -gt 2)
			{
				throw "This cmdlet is only supported in v2 and under. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/replaceAgentInstallationToken"

			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}
        
			if ($StatusCode -eq 200)
			{
				Write-Verbose -Message "Successfully replaced token."
				
				if ($PassThru) 
				{
					Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content).AgentInstallationToken
				}
			}
			else
			{
				throw "There was an issue replacing the installation token: $StatusCode $Reason - $($Result.Content)"
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Get-CEInstallationToken {
	<#
        .SYNOPSIS
			Gets the current installation token.

        .DESCRIPTION
			The cmdlet gets the current installation token.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            $Token = Get-CEInstallationToken

            Gets the current installation token.

        .INPUTS
            None

        .OUTPUTS
           System.String

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 9/11/2017
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -gt 2)
			{
				throw "This cmdlet is only supported in v2 and under. Your account is using v$($SessionInfo.Version)."
			}

			[System.String]$Uri = "$($SessionInfo.Url)/me"

			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Get -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}

			if ($StatusCode -eq 200)
			{
				Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content).AgentInstallationToken
			}
			else
			{
				throw "There was an issue retrieving the agent installation token: $StatusCode $Reason - $($Result.Content)"
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Start-CEDataReplication {
	<#
        .SYNOPSIS
           Starts data replication for specified instances.

        .DESCRIPTION
            The cmdlet starts data replication for specified instances. 

			If invalid IDs are provided, they are ignored and identified in the return data.
			
		.PARAMETER Ids
			The Ids of the instances to start replication for.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER PassThru
			If specified, the cmdlet will return updated instance information as well as a list of invalid IDs.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Start-CEReplication -Ids e0dc06ba-86b5-4c4c-b25b-20a68089c797 -Force

            Starts replication for the specified instance.

        .INPUTS
            System.Guid[]

        .OUTPUTS
           PSCustomObject

			This is a JSON representation of the returned data:
			{
			  "items": [
				{
				  "sourceProperties": {
					"name": "string",
					"disks": [
					  {
						"isProtected": true,
						"name": "string",
						"size": 0
					  }
					],
					"machineCloudState": "string",
					"publicIps": [
					  "string"
					],
					"memory": 0,
					"os": "string",
					"cpu": [
					  {
						"cores": 0,
						"modelName": "string"
					  }
					],
					"machineCloudId": "string"
				  },
				  "replicationInfo": {
					"lastConsistencyDateTime": "2017-09-10T14:19:39Z",
					"nextConsistencyEstimatedDateTime": "2017-09-10T14:19:39Z",
					"rescannedStorageBytes": 0,
					"backloggedStorageBytes": 0,
					"initiationStates": {
					  "items": [
						{
						  "steps": [
							{
							  "status": "NOT_STARTED",
							  "message": "string",
							  "name": "WAITING_TO_INITIATE_REPLICATION"
							}
						  ],
						  "startDateTime": "2017-09-10T14:19:39Z"
						}
					  ],
					  "estimatedNextAttemptDateTime": "2017-09-10T14:19:39Z"
					},
					"replicatedStorageBytes": 0,
					"totalStorageBytes": 0
				  },
				  "license": {
					"startOfUseDateTime": "2017-09-10T14:19:39Z",
					"licenseId": "string"
				  },
				  "id": "string",
				  "replicationStatus": "STOPPED",
				  "replica": "string",
				  "lifeCycle": {
					"failoverDateTime": "2017-09-10T14:19:39Z",
					"cutoverDateTime": "2017-09-10T14:19:39Z",
					"lastTestDateTime": "2017-09-10T14:19:39Z",
					"connectionEstablishedDateTime": "2017-09-10T14:19:39Z",
					"agentInstallationDateTime": "2017-09-10T14:19:39Z"
				  },
				  "isAgentInstalled": true
				}
			  ],
			  "invalidMachineIDs": [
				"string"
			  ]
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	[OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid[]]$Ids = @(),

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			[System.Collections.Hashtable]$SessSplat = @{
				"Session" = $Session
			}

			if ($ProjectId -ne [System.Guid]::Empty)
			{
				$SessSplat.Add("ProjectId", $ProjectId)
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/startReplication"

			[System.String]$Body = ConvertTo-Json -InputObject @{"machineIDs" = $Ids}

			$Target = Get-CETargetCloud @SessSplat | Select-Object -ExpandProperty Cloud

			$ConfirmMessage = @"
Are you sure you want to start data replication?

If you continue, you will begin to incur additional costs from $Target for data transfer, storage, compute and other resources.

(selected instances for which data replication is already started will not be affected)
"@

			$WhatIfDescription = "Started replication for CE Instances $([System.String]::Join(",", $Ids))"
			$ConfirmCaption = "Start Data Replication for $($Ids.Length) Instance$(if ($Ids.Length -gt 1) { "s" })"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Requesting replication for:`r`n$Body"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -ContentType "application/json" -Body $Body -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 200)
				{
					[PSCustomObject]$Temp = ConvertFrom-Json -InputObject $Result.Content

					if ($Temp.Items -ne $null -and $Temp.Items.Length -gt 0)
					{
						Write-Verbose -Message "Replication successfully stopped for machine(s) $([System.String]::Join(",", $($Temp | Select-Object -ExpandProperty Items | Select-Object -ExpandProperty Id)))."

						if ($PassThru)
						{
							Write-Output -InputObject $Temp
						}
					}
					else
					{
						Write-Warning -Message "No items were returned for successful replication stop."
					}

					if ($Temp.InvalidMachineIDs -ne $null -and $Temp.InvalidMachineIDs.Length -gt 0)
					{
						Write-Warning -Message "The following ids were invalid: $([System.String]::Join(",", ($Temp | Select-Object -ExpandProperty InvalidMachineIDs)))" 
					}					
				}
				else
				{
					throw "There was an issue starting replication: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Stop-CEDataReplication {
	<#
        .SYNOPSIS
           Stops data replication for specified instances.

        .DESCRIPTION
            The cmdlet stops data replication for specified instances. The instances will remain in the console, and replication can be started from zero again.

			If invalid IDs are provided, they are ignored and identified in the return data.

		.PARAMETER Ids
			The Ids of the instances to stop replication on.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER PassThru
			If specified, the cmdlet will return updated instance information as well as a list of invalid IDs.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Stop-CEReplication -Ids e0dc06ba-86b5-4c4c-b25b-20a68089c797 -Force

            Stops replication for the specified instance.

        .INPUTS
            System.Guid[]

        .OUTPUTS
			None or PSCustomObject

			This is a JSON representation of the returned data:
			{
				"items": [
				{
				  "sourceProperties": {
					"name": "string",
					"disks": [
					  {
						"isProtected": true,
						"name": "string",
						"size": 0
					  }
					],
					"machineCloudState": "string",
					"publicIps": [
					  "string"
					],
					"memory": 0,
					"os": "string",
					"cpu": [
					  {
						"cores": 0,
						"modelName": "string"
					  }
					],
					"machineCloudId": "string"
				  },
				  "replicationInfo": {
					"lastConsistencyDateTime": "2017-09-10T14:19:39Z",
					"nextConsistencyEstimatedDateTime": "2017-09-10T14:19:39Z",
					"rescannedStorageBytes": 0,
					"backloggedStorageBytes": 0,
					"initiationStates": {
					  "items": [
						{
						  "steps": [
							{
							  "status": "NOT_STARTED",
							  "message": "string",
							  "name": "WAITING_TO_INITIATE_REPLICATION"
							}
						  ],
						  "startDateTime": "2017-09-10T14:19:39Z"
						}
					  ],
					  "estimatedNextAttemptDateTime": "2017-09-10T14:19:39Z"
					},
					"replicatedStorageBytes": 0,
					"totalStorageBytes": 0
				  },
				  "license": {
					"startOfUseDateTime": "2017-09-10T14:19:39Z",
					"licenseId": "string"
				  },
				  "id": "string",
				  "replicationStatus": "STOPPED",
				  "replica": "string",
				  "lifeCycle": {
					"failoverDateTime": "2017-09-10T14:19:39Z",
					"cutoverDateTime": "2017-09-10T14:19:39Z",
					"lastTestDateTime": "2017-09-10T14:19:39Z",
					"connectionEstablishedDateTime": "2017-09-10T14:19:39Z",
					"agentInstallationDateTime": "2017-09-10T14:19:39Z"
				  },
				  "isAgentInstalled": true
				}
			  ],
			  "invalidMachineIDs" : [
				"string"
			  ]
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	[OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid[]]$Ids = @(),

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/stopReplication"

			[System.String]$Body = ConvertTo-Json -InputObject @{"machineIDs" = $Ids}

			$ConfirmMessage = @"
Are you sure you want to stop data replication?

If you continue, all replicated data for $(if ($Ids.Length -gt 1) { "these instances" } else { "this instance" }) will be purged and you will no longer be able to launch Target instances for either testing purposes or for Cutover.

$(if ($Ids.Length -gt 1) { "These instances" } else { "This instance" }) will still appear in this Console and you will be able to restart data replication for $(if ($Ids.Length -gt 1) { "them" } else { "it" }) whenever you wish, however data replication will then begin from zero.

(selected instances for which data replication is already stopped will not be affected)
"@

			$WhatIfDescription = "Stopped replication for CE Instances $([System.String]::Join(",", $Ids))"
			$ConfirmCaption = "Stop Data Replication for $($Ids.Length) Instance$(if ($Ids.Length -gt 1) { "s" })"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Requesting to stop replication for:`r`n$Body"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -ContentType "application/json" -Body $Body -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 200)
				{
					[PSCustomObject]$Temp = ConvertFrom-Json -InputObject $Result.Content

					if ($Temp.Items -ne $null -and $Temp.Items.Length -gt 0)
					{
						Write-Verbose -Message "Replication successfully stopped for machine(s) $([System.String]::Join(",", ($Temp | Select-Object -ExpandProperty Items | Select-Object -ExpandProperty Id)))."

						if ($PassThru)
						{
							Write-Output -InputObject $Temp
						}
					}
					else
					{
						Write-Warning -Message "No items were returned for successfull replication stop."
					}

					if ($Temp.InvalidMachineIDs -ne $null -and $Temp.InvalidMachineIDs.Length -gt 0)
					{
						Write-Warning -Message "The following ids were invalid: $([System.String]::Join(",", ($Temp | Select-Object -ExpandProperty InvalidMachineIDs)))" 
					}
				}
				else
				{
					throw "There was an issue stopping replication: $StatusCode $Reason - $($Result.Content)"
				}				
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Suspend-CEDataReplication {
	<#
        .SYNOPSIS
           Pauses data replication for specified instances.

        .DESCRIPTION
            The cmdlet pauses data replication for specified instances. The instances will remain in the console, and replication can be started again.

			If invalid IDs are provided, they are ignored and identified in the return data.

		.PARAMETER Ids
			The Ids of the instances to pause replication on.

		.PARAMETER ProjectId
			The project Id that the specified machines are in. This defaults to the current project retrieved from the login.

		.PARAMETER PassThru
			If specified, the cmdlet will return updated instance information as well as a list of invalid IDs.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Suspend-CEReplication -Ids e0dc06ba-86b5-4c4c-b25b-20a68089c797 -Force

            Pauses replication for the specified instance.

        .INPUTS
            System.Guid[]

        .OUTPUTS
			None or PSCustomObject

			This is a JSON representation of the returned data:
			{
			  "items": [
				{
				  "sourceProperties": {
					"name": "string",
					"disks": [
					  {
						"isProtected": true,
						"name": "string",
						"size": 0
					  }
					],
					"machineCloudState": "string",
					"publicIps": [
					  "string"
					],
					"memory": 0,
					"os": "string",
					"cpu": [
					  {
						"cores": 0,
						"modelName": "string"
					  }
					],
					"machineCloudId": "string"
				  },
				  "replicationInfo": {
					"lastConsistencyDateTime": "2017-10-04T15:34:43Z",
					"nextConsistencyEstimatedDateTime": "2017-10-04T15:34:43Z",
					"rescannedStorageBytes": 0,
					"backloggedStorageBytes": 0,
					"initiationStates": {
					  "items": [
						{
						  "steps": [
							{
							  "status": "NOT_STARTED",
							  "message": "string",
							  "name": "WAITING_TO_INITIATE_REPLICATION"
							}
						  ],
						  "startDateTime": "2017-10-04T15:34:43Z"
						}
					  ],
					  "estimatedNextAttemptDateTime": "2017-10-04T15:34:43Z"
					},
					"replicatedStorageBytes": 0,
					"totalStorageBytes": 0
				  },
				  "license": {
					"startOfUseDateTime": "2017-10-04T15:34:43Z",
					"licenseId": "string"
				  },
				  "id": "string",
				  "replicationStatus": "STOPPED",
				  "replica": "string",
				  "lifeCycle": {
					"lastTestLaunchDateTime": "2017-10-04T15:34:43Z",
					"connectionEstablishedDateTime": "2017-10-04T15:34:43Z",
					"agentInstallationDateTime": "2017-10-04T15:34:43Z",
					"lastCutoverDateTime": "2017-10-04T15:34:43Z",
					"lastRecoveryLaunchDateTime": "2017-10-04T15:34:43Z"
				  },
				  "isAgentInstalled": true
				}
			  ],
			  "invalidMachineIDs": [
				"string"
			  ]
			}

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	[OutputType([PSCustomObject])]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid[]]$Ids = @(),

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3)
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/pauseReplication"

			[System.String]$Body = ConvertTo-Json -InputObject @{"machineIDs" = $Ids}

			$ConfirmMessage = @"
Are you sure you want to pause data replication?

$(if ($Ids.Length -gt 1) { "These instances" } else { "This instance" }) will still appear in this Console and you will be able to restart data replication for $(if ($Ids.Length -gt 1) { "them" } else { "it" }) whenever you wish.

(selected instances for which data replication is already paused or stopped will not be affected)
"@

			$WhatIfDescription = "Paused replication for CE Instances $([System.String]::Join(",", $Ids))"
			$ConfirmCaption = "Pause Data Replication for $($Ids.Length) Instance$(if ($Ids.Length -gt 1) { "s" })"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Requesting to pause replication for:`r`n$Body"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -ContentType "application/json" -Body $Body -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 200)
				{
					[PSCustomObject]$Temp = ConvertFrom-Json -InputObject $Result.Content

					if ($Temp.Items -ne $null -and $Temp.Items.Length -gt 0)
					{
						Write-Verbose -Message "Replication successfully paused for machine(s) $([System.String]::Join(",", ($Temp | Select-Object -ExpandProperty Items | Select-Object -ExpandProperty Id)))."

						if ($PassThru)
						{
							Write-Output -InputObject $Temp
						}
					}
					else
					{
						Write-Warning -Message "No items were returned for successfull replication stop."
					}

					if ($Temp.InvalidMachineIDs -ne $null -and $Temp.InvalidMachineIDs.Length -gt 0)
					{
						Write-Warning -Message "The following ids were invalid: $([System.String]::Join(",", ($Temp | Select-Object -ExpandProperty InvalidMachineIDs)))" 
					}
				}
				else
				{
					throw "There was an issue stopping replication: $StatusCode $Reason - $($Result.Content)"
				}				
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Invoke-CEMachineFailover {
	<#
		.SYNOPSIS
			Spawns a failover job to fail over the specified source machines (Applicable in DR projects only). The source and target locations of the project are reversed: The launched target machines become the new replication source machines, the CloudEndure agent is removed from the previous source machines.

		.DESCRIPTION
			Spawns a failover job to fail over the specified source machines (Applicable in DR projects only). The source and target locations of the project are reversed: The launched target machines become the new replication source machines, the CloudEndure agent is removed from the previous source machines.

		.PARAMETER Ids
			The Ids of the instances to failover. The most recent point in time is used for each.

		.PARAMETER PointInTime
			An array of hashtables specifying the machine Id and Point In Time Id to failover. For example, 

			-PointInTime @(@{"machineId" = "guid"; "pointInTimeId" = "guid" }, @{"machineId" = "guid2"})

			In this case, the first machine uses the specified pointInTimeId, while the second machine uses the latest pointInTime since that property was omitted.

		.PARAMETER UseExistingMachines
			Specify to use only all machines with replicas.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER PassThru
			If specified, the cmdlet will return job information about the failover.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE 
			Invoke-CEMachineFailover -UseExistingMachines -Force

			Invokes a failover for all CE machines with an active replica.

		.EXAMPLE
			Invoke-CEMachineFailover -Ids @(e0dc06ba-86b5-4c4c-b25b-20a68089c797)

			Invokes a failover for the specific instance using the latest point in time.

		.EXAMPLE
			Invoke-CEMachineFailover -PointInTime @(@{"machineId" = "e0dc06ba-86b5-4c4c-b25b-20a68089c797"; "pointInTimeId" = "f1ed17cb-46a3-4dd8-525e-67770123aaef"})

		.INPUTS
			None or System.Guid[]

		.OUTPUTS
			System.Management.Automation.PSCustomObject

			This is a JSON representation of the returned value:
			{
			  "status": "PENDING",
			  "type": "TEST",
			  "id": "string",
			  "log": [
				{
				  "message": "string",
				  "logDateTime": "2017-09-10T14:19:39Z"
				}
			  ]
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH", DefaultParameterSetName = "Latest")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "Latest", Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid[]]$Ids = @(),

		[Parameter(Mandatory = $true, ParameterSetName = "PointInTime", Position = 0)]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$PointInTime = @(),

		[Parameter(ParameterSetName = "Existing")]
		[Switch]$UseExistingMachines,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session.ToLower())
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -gt 2)
			{
				throw "This cmdlet is only supported in v2 and under. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/performFailover"

			$Items = @()

			switch ($PSCmdlet.ParameterSetName)
			{
				"Latest" {
					foreach ($Item in $Ids)
					{
						$Items += @{"machineId" = $Item}
					}

					$Uri += "?useExistingMachines=false"

					break
				}
				"PointInTime" {

					foreach ($Item in $PointInTime)
					{
						[System.Collections.Hashtable]$Machine = @{}

						if ($Item.ContainsKey("machineId"))
						{
							 $Machine.Add("machineId", $Item["machineId"])

							if ($Item.ContainsKey("pointInTimeId"))
							{
								$Machine.Add("pointInTimeId", $Item["pointInTimeId"])
							}

							$Items += $Machine
						}
						else
						{
							throw "The PointInTime array contained an item without a machineId property, this is required for each object."
						}
					}

					$Uri += "?useExistingMachines=false"

					break
				}
				"Existing" {
					$Uri += "?useExistingMachines=true"
					break
				}
				default {
					throw "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
					break
				}
			}

			$ConfirmMessage = @"
Are you sure you want to perform a failover?
"@

			$WhatIfDescription = "Performed a failover for CE Instances."
			$ConfirmCaption = "Perform CE Failover."

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				[System.Collections.Hashtable]$Splat = @{}

				if ($PSCmdlet.ParameterSetName -ne "Existing")
				{
					[System.String]$Body = ConvertTo-Json -InputObject @{"items" = $Items}
					$Splat.Add("Body", $Body)
					$Splat.Add("ContentType", "application/json")

					Write-Verbose -Message "Requesting failover for:`r`n$Body"
				}

				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -WebSession $SessionInfo.Session @Splat -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 202)
				{
					Write-Verbose -Message "Failover successfully started."

					if ($PassThru)
					{
						$Temp = ConvertFrom-Json -InputObject $Result.Content
						Write-Output -InputObject ([PSCustomObject]$Temp)
					}
				}
				else
				{
					throw "There was an issue starting the failover: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Invoke-CEMachineTest {
	<#
		.SYNOPSIS
			Launches a new test for the specified instances.

		.DESCRIPTION
			This cmdlet invokes a new test run of the specified instances.

		.PARAMETER Ids
			The ids of the instances to perform a new test for.

		.PARAMETER PointInTime
			An array of hashtables specifying the machine Id and Point In Time Id to test. For example, 

			-PointInTime @(@{"machineId" = "guid"; "pointInTimeId" = "guid" }, @{"machineId" = "guid2"})

			In this case, the first machine uses the specified pointInTimeId, while the second machine uses the latest pointInTime since that property was omitted.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Invoke-CEMachineTest -Ids @("781ca752-d88f-4408-a37d-90e247f3d569", "681cae52-f88f-4290-a37d-8ae276f3d6da")

			This runs a new test for 2 instances.

		.INPUTS
			System.Guid[]

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject	
	
			This is a JSON representation of the output:
			{
			  "status": "PENDING",
			  "type": "TEST",
			  "id": "string",
			  "log": [
				{
				  "message": "string",
				  "logDateTime": "2017-09-10T14:19:39Z"
				}
			  ]
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH", DefaultParameterSetName = "Latest")]
	[OutputType([PSCustomObject])]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0, ParameterSetName = "Latest")]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid[]]$Ids = @(),

		[Parameter(Mandatory = $true, ParameterSetName = "PointInTime")]
		[ValidateNotNull()]
		[System.Collections.Hashtable[]]$PointInTime = @(),

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force
	)

	Begin {
	}

	Process {
		if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
            $Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -gt 2)
			{
				throw "This cmdlet is only supported in v2 and under. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/performTest"

			$Items = @()

			switch ($PSCmdlet.ParameterSetName)
			{
				"Latest" {

					foreach ($Item in $Ids)
					{
						$Items += @{"machineId" = $Item}
					}

					break
				}
				"PointInTime" {

					foreach ($Item in $PointInTime)
					{
						[System.Collections.Hashtable]$Machine = @{}

						if ($Item.ContainsKey("machineId"))
						{
							 $Machine.Add("machineId", $Item["machineId"])

							if ($Item.ContainsKey("pointInTimeId"))
							{
								$Machine.Add("pointInTimeId", $Item["pointInTimeId"])
							}

							$Items += $Machine
						}
						else
						{
							throw "The PointInTime array contained an item without a machineId property, this is required for each object."
						}
					}

					break
				}
				default {
					throw "Encountered an unknown parameter set $($PSCmdlet.ParameterSetName)."
					break
				}
			}

			$ConfirmMessage = @"
This test will launch a new instance for each of the launchable Source instances that you have selected.

In addition, the Source instance will be marked as "tested" on this date.

Note:
Any previously launched versions of these instances (including any associated cloud resources that were created by CloudEndure) will be deleted.
"@
			$WhatIfDescription = "Ran test for $($Ids.Length) instance$(if ($Ids.Length -gt 1) { "s" })."
			$ConfirmCaption = "Test $($Ids.Length) Instance$(if ($Ids.Length -gt 1) { "s" })"

			[System.String]$Body = ConvertTo-Json -InputObject @{"items" = $Items}

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Requesting tests for:`r`n$Body"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -Body $Body -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				# 202 = Accepted
				if ($StatusCode -eq 202)
				{
					Write-Verbose -Message "Test successfully initiated."
					
					if ($PassThru)
					{
						Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
					}
				}
				else
				{
					throw "There was an issue launching the test: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Invoke-CEMachineCutover {
	<#
		.SYNOPSIS
			Launches a cutover for the specified instances.

		.DESCRIPTION
			This cmdlet invokes a cutover of the specified instances.

		.PARAMETER Ids
			The ids of the instances to perform a cutover for.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

		.PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Invoke-CEMachineCutover -Ids @("781ca752-d88f-4408-a37d-90e247f3d569", "681cae52-f88f-4290-a37d-8ae276f3d6da")

			This runs a cutover for 2 instances.

		.INPUTS
			System.Guid[]

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject	
	
			This is a JSON representation of the output:
			{
			  "status": "PENDING",
			  "type": "TEST",
			  "id": "string",
			  "log": [
				{
				  "message": "string",
				  "logDateTime": "2017-09-10T14:19:39Z"
				}
			  ]
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 9/11/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([PSCustomObject[]])]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
        [System.Guid[]]$Ids = @(),

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty,

		[Parameter()]
		[Switch]$Force
	)

	Begin {
	}

	Process {
		if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
            $Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -gt 2)
			{
				throw "This cmdlet is only supported in v2 and under. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/performCutover?useExistingMachines=false"

			$ConfirmMessage = @"
This Cutover will launch a new instance for each of the launchable Source instances that you have selected.

In addition, the Source instance will be marked as "Cutover" on this date.

Note:
Any previously launched versions of these instances (including any associated cloud resources that were created by CloudEndure) will be deleted.
"@
			$WhatIfDescription = "Cutover $($Ids.Length) instance$(if ($Ids.Length -gt 1) { "s" })."
			$ConfirmCaption = "Cutover $($Ids.Length) Instance$(if ($Ids.Length -gt 1) { "s" })"

			$Body = @{"items" = @()}

			foreach ($Id in $Ids)
			{
				$Body.items += @{"machineId" = $Id}
			}

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Requesting cutover for:`r`n $(ConvertTo-Json -InputObject $Body)"
				
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -Body (ConvertTo-Json -InputObject $Body) -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				# 202 = Accepted
				if ($StatusCode -eq 202)
				{
					Write-Verbose -Message "Cutover successfully initiated."
					
					if ($PassThru)
					{
						Write-Output -InputObject ([PSCustomObject[]](ConvertFrom-Json -InputObject $Result.Content))
					}
				}
				else
				{
					throw "There was an issue launching the cutover: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else {
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Get-CEJobs {
    <#
        .SYNOPSIS
           Gets the log information from active CE jobs.

        .DESCRIPTION
            The cmdlet lists all of log information about a currently running CE jobs.

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.
            
        .EXAMPLE
            Get-CEJobs

            Gets the log data for active jobs.

        .INPUTS
			None

        .OUTPUTS
			System.Management.Automation.PSCustomObject or System.Management.Automation.PSCustomObject[]

			This is a JSON representation of the returned array:
			[
				{
				  "status": "PENDING",
				  "type": "TEST",
				  "id": "string",
				  "log": [
					{
					  "message": "string",
					  "logDateTime": "2017-09-10T14:19:39Z"
					}
				  ]
				}
			]

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject], [System.Management.Automation.PSCustomObject[]])]
    Param(
		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$Id = [System.Guid]::Empty,

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
    )

    Begin {        
    }

    Process {
        $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/jobs"

			if ($Id -ne [System.Guid]::Empty)
			{
				$Uri += "/$($Id.ToString())"
			}
        
			$StatusCode = 0
			$Reason = ""

			try {
				[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Get -WebSession $SessionInfo.Session -ErrorAction Stop
				$StatusCode = $Result.StatusCode
				$Reason = $Result.StatusDescription
			}
			catch [System.Net.WebException] {
				[System.Net.WebException]$Ex = $_.Exception

				if ($Ex.Response -eq $null)
				{
					$Reason = "$($Ex.Status): $($Ex.Message)"
					$StatusCode = 500
				}
				else
				{
					[System.Net.HttpWebResponse]$Response = $Ex.Response
					$StatusCode = [System.Int32]$Response.StatusCode
			
					[System.IO.Stream]$Stream = $Response.GetResponseStream()
					[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
					[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
					$Content = $Reader.ReadToEnd()

					$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
				}
			}
			catch [Exception]  {
				$Reason = $_.Exception.Message
			}

			if ($StatusCode -eq 200)
			{
				if ($Id -ne [System.Guid]::Empty)
				{
					Write-Output -InputObject ([PSCustomObject[]](ConvertFrom-Json -InputObject $Result.Content).Items)
				}
				else
				{
					Write-Output -InputObject ([PSCustomObject](ConvertFrom-Json -InputObject $Result.Content))
				}
			}										
			else
			{
				throw "There was an issue getting the jobs: $StatusCode $Reason - $($Result.Content)"
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
    }

    End {
    }
}

Function Invoke-CEReplicaCleanup {
	<#
		.SYNOPSIS
			Spawns a cleanup job to remove the specified target machines from the cloud.

		.DESCRIPTION
			Spawns a cleanup job to remove the specified target machines from the cloud.

		.PARAMETER Ids
			The list of replica IDs to delete (corresponding to the 'replica' field in the machine object).

		.PARAMETER ProjectId
			The project Id to use to retrieve the details. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			Returns the job created by the cmdlet.

		.EXAMPLE
			Invoke-CEReplicaCleanup -Ids @("3a0b0738-e46d-489b-a735-5856a1eafb49")

			Begins a cleanup job for the replica instance indicated by the supplied id.

		.INPUTS
			System.Guid[]

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject

			This is a JSON representation of the returned value:
			{
			  "status": "PENDING",
			  "type": "TEST",
			  "id": "string",
			  "log": [
				{
				  "message": "string",
				  "logDateTime": "2017-09-10T14:19:39Z"
				}
			  ]
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid[]]$Ids = @(),

		[Parameter()]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[Switch]$Force,

        [Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}
	
	Process {
		 $SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/replicas"

			[System.String]$Body = ConvertTo-Json -InputObject @{"replicaIDs" = $Ids}

			$ConfirmMessage = @"
This cleanup will remove the specified target machines from the cloud.
"@
			$WhatIfDescription = "Cleaned up $($Ids.Length) instance$(if ($Ids.Length -gt 1) { "s" })."
			$ConfirmCaption = "Cleanup $($Ids.Length) Instance$(if ($Ids.Length -gt 1) { "s" })"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Delete -Body $Body -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				if ($StatusCode -eq 202)
				{
					Write-Verbose -Message "Cleanup successfully started."

					if ($PassThru)
					{
						Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content)
					}
				}
				else
				{
					throw "There was an issue launching the cleanup: $StatusCode $Reason - $($Result.Content)"
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}
	}

	End {
	}
}

Function Invoke-CEReverseReplication {
	<#
		.SYNOPSIS
			Reverses replication for a DR project.

		.DESCRIPTION
			This cmdlet reverses the direction of replication for a DR project.

		.PARAMETER ProjectId
			The project Id to reverse replication for. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.PARAMETER PassThru
			Returns the job created by the cmdlet.

		.EXAMPLE
			Invoke-CEReverseReplication 

			Reverses replication for the current project stored in the session.

		.INPUTS
			System.Guid

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject

			This is a JSON representation of the returned value:
			{
			  "status": "PENDING",
			  "type": "TEST",
			  "id": "string",
			  "log": [
				{
				  "message": "string",
				  "logDateTime": "2017-09-10T14:19:39Z"
				}
			  ]
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3)
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/reverseReplication"

			$ConfirmMessage = @"
This will reverse the direction of replication for the project $ProjectId.
"@
			$WhatIfDescription = "Reversed replication for project $ProjectId."
			$ConfirmCaption = "Reverse Replication For Project"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				switch ($StatusCode)
				{
					200 {
						Write-Verbose -Message "Replication reversal successful."

						if ($PassThru)
						{
							Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content)
						}
						break
					}
					400 {
						throw "There is already another job running: $($Result.Content)"
					}
					422 {
						throw "The project $ProjectId cannot be reversed."
					}
					default {
						throw "There was an issue reversing replication: $StatusCode $Reason - $($Result.Content)"
					}
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}

	}

	End {

	}
}

Function Invoke-CELaunchTargetMachine {
	<#
		.SYNOPSIS
			Launch target machines for test, recovery or cutover.

		.DESCRIPTION
			This cmdlet launches target machines for test, recovery or cutover.

		.PARAMETER LaunchType
			Specify TEST, RECOVERY, or CUTOVER.

		.PARAMETER Ids
			The Ids of the CE machines to launch. Specifying this parameter will use the latest point in time for each machine.

		.PARAMETER Items
			An array of Id and PointInTime Id objects (specified as Hashtables). If the point in time Id is omitted, the latest point in time is used. For example:

			@(
				@{"Id" = "3a0b0738-e46d-489b-a735-5856a1eafb49"; "PointInTimeId" = "4b73848c-9d02-41e5-ac17-a79cf0e3b919"}
				@{"Id" = "f1ffcc9b-8988-4273-acba-96828ef24b0e"}
			)

		.PARAMETER ProjectId
			The project Id that the machines are part of. This defaults to the current project retrieved from the login.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Invoke-CELaunchTargetMachine -LaunchType TEST -Ids @("f1ffcc9b-8988-4273-acba-96828ef24b0e")

			Launches a new test instance for migration for the specified machine id.

		.INPUTS
			None or System.Collections.Hashtable[]

		.OUTPUTS
			None or System.Management.Automation.PSCustomObject

			This is a JSON representation of the returned value:
			{
			  "status": "PENDING",
			  "type": "TEST_LAUNCH",
			  "id": "string",
			  "log": [
				{
				  "message": "string",
				  "logDateTime": "2017-10-04T15:34:43Z"
				}
			  ]
			}

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(

		[Parameter(Mandatory = $true)]
		[ValidateSet("TEST", "RECOVERY", "CUTOVER")]
		[System.String]$LaunchType,

		[Parameter(Mandatory = $true, ParameterSetName = "Ids")]
		[System.Guid[]]$Ids,

		[Parameter(Mandatory = $true, ParameterSetName = "Items")]
		[System.Collections.Hashtable[]]$Items,

		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[Switch]$PassThru,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3)
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			if ($PSCmdlet.ParameterSetName -eq "Ids")
			{
				$Items = @()
				foreach ($Item in $Ids)
				{
					$Items += @{"Id" = $Item}
				}
			}

			[System.Collections.Hashtable]$Request = @{ "launchType" = $LaunchType; "items" = $Items}
			[System.String]$Body = ConvertTo-Json -InputObject $Request

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/launchMachines"

			$ConfirmMessage = @"
This $LaunchType will launch a new instance for each of the launchable Source instances that you have selected.

In addition, the Source instance will be marked as $(switch ($LaunchType) { "CUTOVER" { "cutover"; break; } "TEST" { "tested"; break; } "RECOVERY" {"recovered"; break;}}) on this date.

Note:
Any previously launched versions of these instances (including any associated cloud resources that were created by CloudEndure) will be deleted.
"@
			$WhatIfDescription = "$LaunchType $($Items.Length) instance$(if ($Items.Length -gt 1) { "s" })."
			$ConfirmCaption = "$LaunchType $($Items.Length) Instance$(if ($Items.Length -gt 1) { "s" })"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Requesting $LaunchType for:`r`n $Body"

				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -Body $Body -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				switch ($StatusCode)
				{
					200 {
						Write-Verbose -Message "Replication reversal successful."

						if ($PassThru)
						{
							Write-Output -InputObject (ConvertFrom-Json -InputObject $Result.Content)
						}
						break
					}
					400 {
						throw "There is already another job running: $($Result.Content)"
					}
					422 {
						throw "The project $ProjectId cannot be reversed."
					}
					default {
						throw "There was an issue reversing replication: $StatusCode $Reason - $($Result.Content)"
					}
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}

	}

	End {

	}
}

Function Move-CEMachine {
	<#
		.SYNOPSIS
			Moves machines to another project

		.DESCRIPTION
			This cmdlet moves CE machines from one project to another.

		.PARAMETER Ids
			The Ids of the CE machines to move.

		.PARAMETER ProjectId
			The project Id that the machines are part of. This defaults to the current project retrieved from the login.

		.PARAMETER DestinationProjectId
			The project Id that the machines will be moved to.

        .PARAMETER Session
            The session identifier provided by New-CESession. If this is not specified, the default session information will be used.

		.EXAMPLE
			Move-CEMachine -Ids @("f1ffcc9b-8988-4273-acba-96828ef24b0e") -DestinationProjectId d33213b9-cf05-4a19-9b3c-45605a14eaea

			Moves the specified instances from the default current project to the specified destination project.

		.INPUTS
			System.Guid[]

		.OUTPUTS
			None

		.NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/9/2017
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "HIGH")]
	[OutputType([System.Management.Automation.PSCustomObject])]
	Param(
		[Parameter(Mandatory = $true, Position = 1)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$DestinationProjectId,

		[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
		[System.Guid[]]$Ids,

		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[ValidateScript({
			$_ -ne [System.Guid]::Empty
		})]
		[System.Guid]$ProjectId = [System.Guid]::Empty,

		[Parameter()]
		[Switch]$Force,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
			$script:Sessions.ContainsKey($_.ToLower())
		})]
        [System.String]$Session = [System.String]::Empty
	)

	Begin {
	}

	Process {
		$SessionInfo = $null

        if (-not [System.String]::IsNullOrEmpty($Session)) {
            $SessionInfo = $script:Sessions.Get_Item($Session)
        }
        else {
            $SessionInfo = $script:Sessions.GetEnumerator() | Select-Object -First 1 -ExpandProperty Value
			$Session = $SessionInfo.User.Username
        }

		if ($SessionInfo -ne $null) 
		{
			if ($SessionInfo.Version -ne "latest" -and $SessionInfo.Version -lt 3)
			{
				throw "This cmdlet is only supported in v3 and later. Your account is using v$($SessionInfo.Version)."
			}

			if ($ProjectId -eq [System.Guid]::Empty)
			{
				$ProjectId = $SessionInfo.ProjectId
			}

			[System.Collections.Hashtable]$Request = @{ "destinationProjectId" = $DestinationProjectId; "machineIDs" = $Ids}
			[System.String]$Body = ConvertTo-Json -InputObject $Request

			[System.String]$Uri = "$($SessionInfo.Url)/projects/$ProjectId/moveMacines"

			$ConfirmMessage = @"
This will move $($Ids.Length) instance$(if ($Ids.Length -gt 1) { "s" }) from project $ProjectId to $DestinationProjectId.
"@
			$WhatIfDescription = "Moved $($Ids.Length) instance$(if ($Items.Length -gt 1) { "s" })."
			$ConfirmCaption = "Move $($Ids.Length) Instance$(if ($Items.Length -gt 1) { "s" })"

			if ($Force -or $PSCmdlet.ShouldProcess($WhatIfDescription, $ConfirmMessage, $ConfirmCaption))
			{
				Write-Verbose -Message "Moving machines:`r`n $Body"

				$StatusCode = 0
				$Reason = ""

				try {
					[Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Result = Invoke-WebRequest -Uri $Uri -Method Post -Body $Body -ContentType "application/json" -WebSession $SessionInfo.Session -ErrorAction Stop
					$StatusCode = $Result.StatusCode
					$Reason = $Result.StatusDescription
				}
				catch [System.Net.WebException] {
					[System.Net.WebException]$Ex = $_.Exception

					if ($Ex.Response -eq $null)
					{
						$Reason = "$($Ex.Status): $($Ex.Message)"
						$StatusCode = 500
					}
					else
					{
						[System.Net.HttpWebResponse]$Response = $Ex.Response
						$StatusCode = [System.Int32]$Response.StatusCode
			
						[System.IO.Stream]$Stream = $Response.GetResponseStream()
						[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
						[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
						$Content = $Reader.ReadToEnd()

						$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
					}
				}
				catch [Exception]  {
					$Reason = $_.Exception.Message
				}

				switch ($StatusCode)
				{
					204 {
						Write-Verbose -Message "The move was succesful."

						break
					}
					404 {
						throw "A machine or project not found in account.`r`n$($Result.Content)"
					}
					409 {
						throw "Machines could not be moved due to a conflict:`r`n$($Result.Content)"
					}
					default {
						throw "There was an issue moving the machines: $StatusCode $Reason - $($Result.Content)"
					}
				}
			}
		}
		else 
		{
			throw "A valid Session could not be found with the information provided. Check your active sessions with Get-CESession or create a new session with New-CESession."
		}

	}

	End {

	}
}

#endregion

#region Misc

Function Get-CEWindowsInstaller {
	<#
        .SYNOPSIS
			Downloads the CloudEndure windows installer.

        .DESCRIPTION
			The cmdlet downloads the installer to a location you specify.

        .PARAMETER Destination
			The location the installer should be downloaded to. This can be either a folder or a file name, such as

			c:\downloads or c:\downloads\installer.exe. If a filename is not specified, the filename of the file will be used.
            
        .EXAMPLE
            Get-CEWindowsInstaller -Destination c:\

            Downloads the windows installer to the c: drive.

        .INPUTS
            System.String

        .OUTPUTS
           None

        .NOTES
            AUTHOR: Michael Haken
			LAST UPDATE: 10/6/2017
    #>
    [CmdletBinding()]
    [OutputType()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[System.String]$Destination
    )

    Begin {        
    }

    Process {

		if (Test-Path -Path $Destination -PathType Container)
		{
			$Destination = Join-Path -Path $Destination -ChildPath "installer_win.exe"
		}
		else {
			# The regex is starts with c: or \ and then one or more \dir pieces and then an extension with .ab with 2 or more characters
			# https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx Defines the non-allowed file path characters
			if ($Destination -imatch "^(?:[a-zA-Z]:|\\)(?:\\[^<>:`"\/\\|\?\*]+)+\.[^<>:`"\/\\|\?\*]{2,}$")
			{
				# Then the provided path is a file name, make sure the directory exists
				
				[System.IO.FileInfo]$FileInfo = New-Object -TypeName System.IO.FileInfo($Destination)
				if (-not (Test-Path -Path $FileInfo.Directory.FullName))
				{
					New-Item -Path $FileInfo.Directory.FullName -ItemType Directory
				}
			}
			else
			{
				# Treat the path as a directory, make sure it exists
				if (-not (Test-Path -Path $Destination))
				{
					New-Item -Path $Destination -ItemType Directory
				}

				$Destination = Join-Path -Path $Destination -ChildPath "installer_win.exe"
			}
		}

		$StatusCode = 0
		$Reason = ""

		try {
			# Now we know the folder for the destination exists and the destination path includes a file name
			# OutFile writes the file to the provided path
			# PassThru is only an option with OutFile and returns the result to the pipeline
			[Microsoft.PowerShell.Commands.WebResponseObject]$Result = Invoke-WebRequest -Uri $script:Installer -OutFile $Destination -PassThru -ErrorAction Stop
			$StatusCode = $Result.StatusCode
			$Reason = $Result.StatusDescription
		}
		catch [System.Net.WebException] {
			[System.Net.WebException]$Ex = $_.Exception

			if ($Ex.Response -eq $null)
			{
				$Reason = "$($Ex.Status): $($Ex.Message)"
				$StatusCode = 500
			}
			else
			{
				[System.Net.HttpWebResponse]$Response = $Ex.Response
				$StatusCode = [System.Int32]$Response.StatusCode
			
				[System.IO.Stream]$Stream = $Response.GetResponseStream()
				[System.Text.Encoding]$Encoding = [System.Text.Encoding]::GetEncoding("utf-8")
				[System.IO.StreamReader]$Reader = New-Object -TypeName System.IO.StreamReader($Stream, $Encoding)
				$Content = $Reader.ReadToEnd()

				$Reason = "$($Response.StatusDescription) $($_.Exception.Message)`r`n$Content"
			}
		}
		catch [Exception]  {
			$Reason = $_.Exception.Message
		}

		if ($StatusCode -ne 200) {
			throw "There was an issue downloading this file to $Destination`: $StatusCode $Reason - $($Result.Content)"
		}
		else {
			Write-Verbose -Message "Download compeleted successfully."
		}
    }

    End {
    }
}

#endregion