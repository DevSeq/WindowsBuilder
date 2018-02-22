will {
	$hklmMountPath = 'HKLM\' + $BuildEnv.registryMountPoint.'Windows/System32/config/SOFTWARE'.Substring(6)	
    if (Test-Path $BuildEnv.registryMountPoint.'Windows/System32/config/SOFTWARE')
    {
        say ("Dismounting registry hive: {0}" -f $hklmMountPath)
        reg.exe UNLOAD $hklmMountPath
    }
    else
    {
    	say ("The registry hive does not require dismounting: {0}" -f $hklmMountPath)
    }

    $hkduMountPoint = 'HKLM\' + $BuildEnv.registryMountPoint.'Windows/System32/config/DEFAULT'.Substring(6)
    if (Test-Path $BuildEnv.registryMountPoint.'Windows/System32/config/DEFAULT')
    {
        say ("Dismounting registry hive: {0}" -f $hkduMountPoint)
        reg.exe UNLOAD $hkduMountPoint
    }
    else
    {
        say ("The registry hive does not require dismounting: {0}" -f $hkduMountPoint)
    }

    $hkuMountPoint = 'HKLM\' + $BuildEnv.registryMountPoint.'Users/Default/NTUSER.DAT'.Substring(6)
    if (Test-Path $BuildEnv.registryMountPoint.'Users/Default/NTUSER.DAT')
    {
        say ("Dismounting registry hive: {0}" -f $hkuMountPoint)
        reg.exe UNLOAD $hkuMountPoint
    }
    else
    {
        say ("The registry hive does not require dismounting: {0}" -f $hkuMountPoint)
    }
}

task default -depends Finalize

task Precheck {
	assert ($BuildEnv.themeColor) "The themeColor entry is empty or undefined."
}

task MountRegistry -depends Precheck {
	$regFile = Join-Path $BuildEnv.mountDir -ChildPath 'Windows/System32/config/SOFTWARE'
	$regPath = $BuildEnv.registryMountPoint.'Windows/System32/config/SOFTWARE'
	$hklmMountPath = 'HKLM\' + $regPath.Substring(6)

    say ("Mounting registry to hive: {0} --> {1}" -f $regFile, $hklmMountPath)
	reg.exe LOAD $hklmMountPath $regFile


    $regFile = Join-Path $BuildEnv.mountDir -ChildPath 'Windows/System32/config/DEFAULT'
    $regPath = $BuildEnv.registryMountPoint.'Windows/System32/config/DEFAULT'
    $hkduMountPath = 'HKLM\' + $regPath.Substring(6)

    say ("Mounting registry to hive: {0} --> {1}" -f $regFile, $hkduMountPath)
    reg.exe LOAD $hkduMountPath $regFile


    $regFile = Join-Path $BuildEnv.mountDir -ChildPath 'Users/Default/NTUSER.DAT'
    $regPath = $BuildEnv.registryMountPoint.'Users/Default/NTUSER.DAT'
    $hkuMountPath = 'HKLM\' + $regPath.Substring(6)

    say ("Mounting registry to hive: {0} --> {1}" -f $regFile, $hkuMountPath)
    reg.exe LOAD $hkuMountPath $regFile
}

task ModifyRegistry -depends MountRegistry {
    $dwmBasePath = $BuildEnv.registryMountPoint.'Windows/System32/config/DEFAULT' + '\Software\Microsoft\Windows\DWM'
    $explorerAccentPath = $BuildEnv.registryMountPoint.'Windows/System32/config/DEFAULT' + '\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'

    $userDwmBasePath = $BuildEnv.registryMountPoint.'Users/Default/NTUSER.DAT' + '\Software\Microsoft\Windows\DWM'
    $userExplorerAccentPath = $BuildEnv.registryMountPoint.'Users/Default/NTUSER.DAT' + '\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'

    @($explorerAccentPath, $userExplorerAccentPath) | ForEach-Object {
        if (-not (Test-Path $_))
        {
            md $_ | Out-Null
        }
    }

    $dwmProps = @(
        'AccentColor'
        'AccentColorInactive'
    )

    $dwmProps | ForEach-Object {
        if ($BuildEnv.themeColor."$_")
        {
            say ("Set DWM: {0} = {1}" -f $_, $BuildEnv.themeColor."$_")

            $dwmPropName = $_
            $dwmPropValue = $BuildEnv.themeColor."$_"

            @($dwmBasePath, $userDwmBasePath) | ForEach-Object {
                Get-ItemProperty -Path $_ -Name $dwmPropName -ErrorAction SilentlyContinue -ErrorVariable getPropErr
                if (-not $getPropErr)
                {
                    Remove-ItemProperty -Path $_ -Name $dwmPropName
                }
                New-ItemProperty -Path $_ -Name $dwmPropName -PropertyType DWord -Value $dwmPropValue
            }
        }
    }

    $explorerProps = @(
        'AccentPalette'
        'StartColorMenu'
        'AccentColorMenu'
    )

    $explorerProps | ForEach-Object {
        if ($BuildEnv.themeColor."$_")
        {
            say ("Set Explorer Accent: {0} = {1}" -f $_, $BuildEnv.themeColor."$_")

            $expPropName = $_
            $expPropValue = $BuildEnv.themeColor."$_"

            @($explorerAccentPath, $userExplorerAccentPath) | ForEach-Object {
                Get-ItemProperty -Path $_ -Name $expPropName -ErrorAction SilentlyContinue -ErrorVariable getPropErr

                if (-not $getPropErr)
                {
                    Remove-ItemProperty -Path $_ -Name $expPropName
                }

                if ($expPropName -eq 'AccentPalette')
                {
                    $propType = 'Binary'
                    $propValue = $expPropValue.Split(',') | % { [byte]"0x$_" }
                }
                else
                {
                    $propType = 'DWord'
                    $propValue = $expPropValue
                }

                New-ItemProperty -Path $_ -Name $expPropName -PropertyType $propType -Value $propValue
            }
        }
    }

    
    $extraAccentsPath = $BuildEnv.registryMountPoint.'Windows/System32/config/SOFTWARE' + '\Microsoft\Windows\CurrentVersion\Themes\Accents'

    $themePaths = @(
        '\0\Theme0'
        '\0\Theme1'
        '\1\Theme0'
        '\1\Theme1'
        '\2\Theme0'
        '\2\Theme1'
        '\3\Theme0'
        '\3\Theme1'
    )

    if ($BuildEnv.themeColor.oemColors.Count -gt 0)
    {
        for ($i = 0; $i -lt $BuildEnv.themeColor.oemColors.Count; $i++)
        {
            if (-not $BuildEnv.themeColor.oemColors[$i])
            {
                break
            }

            say ("Set OEM accent color #{0}: {1}" -f $i, $BuildEnv.themeColor.oemColors[$i])

            $accentFullPath = $extraAccentsPath + $themePaths[$i]
            if (-not (Test-Path $accentFullPath))
            {
                md $accentFullPath -Force | Out-Null
            }

            Get-ItemProperty -Path $accentFullPath -Name Color -ErrorAction SilentlyContinue -ErrorVariable getPropErr
            if (-not $getPropErr)
            {
                Remove-ItemProperty $accentFullPath -Name Color
            }
            
            New-ItemProperty -Path $accentFullPath -Name Color -PropertyType DWord -Value $BuildEnv.themeColor.oemColors[$i]
        }
    }
}

task DismountRegistry -depends ModifyRegistry {
	$regFile = Join-Path $BuildEnv.mountDir -ChildPath 'Windows/System32/config/SOFTWARE'
	$regPath = $BuildEnv.registryMountPoint.'Windows/System32/config/SOFTWARE'
	$hklmMountPath = 'HKLM\' + $regPath.Substring(6)
    say ("Dismounting registry hive: {0}" -f $hklmMountPath)
	reg.exe UNLOAD $hklmMountPath

    $regFile = Join-Path $BuildEnv.mountDir -ChildPath 'Windows/System32/config/DEFAULT'
    $regPath = $BuildEnv.registryMountPoint.'Windows/System32/config/DEFAULT'
    $hkduMountPath = 'HKLM\' + $regPath.Substring(6)
    say ("Dismounting registry hive: {0}" -f $hkduMountPath)
    reg.exe UNLOAD $hkduMountPath

    $regFile = Join-Path $BuildEnv.mountDir -ChildPath 'Users/Default/NTUSER.DAT'
    $regPath = $BuildEnv.registryMountPoint.'Users/Default/NTUSER.DAT'
    $hkuMountPath = 'HKLM\' + $regPath.Substring(6)
    say ("Dismounting registry hive: {0}" -f $hkuMountPath)
    reg.exe UNLOAD $hkuMountPath
}

task Finalize -depends Precheck, DismountRegistry {
	say 'Done!'
}