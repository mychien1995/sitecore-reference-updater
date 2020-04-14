[System.Reflection.Assembly]::LoadWithPartialName("System.Xml.Linq") | Out-Null

$scanned = New-Object Collections.Generic.List[string]

Function Update-Reference{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Item]$CurrentItem,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Item]$OldSite,
        [Parameter(Mandatory = $true, Position = 3)]
        [Item]$NewSite,
        [Parameter(Mandatory = $false, Position = 4)]
        [string[]]$Exclude
    )
    if((Is-Ancestor $CurrentItem $NewSite.ID) -or $CurrentItem.ID -eq $NewSite.ID){
        Update-ItemReference $CurrentItem $OldSite $NewSite
        Get-ChildItem -Path $CurrentItem.Paths.FullPath | ForEach-Object{
            $child = [Sitecore.Data.Items.Item]$_
            if($Exclude -and ($Exclude.IndexOf($child.Name) -eq -1) -and ($Exclude.IndexOf($child.ID.ToString()) -eq -1)){
                Update-ItemReference $child $OldSite $NewSite $Exclude
            }
            
        }
    }
}
Function Update-ItemReference{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Item]$CurrentItem,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Item]$OldSite,
        [Parameter(Mandatory = $true, Position = 3)]
        [Item]$NewSite,
        [Parameter(Mandatory = $false, Position = 4)]
        [string[]]$Exclude
    )
    if($scanned.IndexOf($CurrentItem.ID.ToString()) -eq -1){
        Write-Host ('Scan item: {0}' -f $CurrentItem.Paths.FullPath)
        $scanned.Add($CurrentItem.ID.ToString());
        $CurrentItem.Editing.BeginEdit();
        $CurrentItem.Fields.ReadAll()
        $CurrentItem.Fields | ForEach-Object{
        $field = [Sitecore.Data.Fields.Field]$_
            $fieldType = $field.Type.ToLower()
            if($fieldType -eq 'droplink'){
                Update-ReferenceField $field $OldSite $NewSite
            }
            elseif($fieldType -eq 'droptree'){
                Update-ReferenceField $field $OldSite $NewSite
            }
            elseif($fieldType -eq 'general link'){
                Update-LinkField $field $OldSite $NewSite
            }
            elseif($fieldType -eq 'layout'){
                Update-LayoutField $field $OldSite $NewSite
            }
        }
        $CurrentItem.Editing.EndEdit();
        Get-ChildItem -Path $CurrentItem.Paths.FullPath | ForEach-Object {
            $child = [Sitecore.Data.Items.Item]$_
            if($Exclude -and ($Exclude.IndexOf($child.Name) -eq -1) -and ($Exclude.IndexOf($child.ID.ToString()) -eq -1)){
                Update-ItemReference $child $OldSite $NewSite $Exclude
            }
        }
    }
}

Function Update-LayoutField{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Sitecore.Data.Fields.Field]$field,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Item]$OldSite,
        [Parameter(Mandatory = $true, Position = 3)]
        [Item]$NewSite
    )
    $layoutField = [Sitecore.Data.Fields.LayoutField]$field
    $layoutValue = $layoutField.Value
    if($layoutValue -and $layoutValue -ne $null -and $layoutValue -ne ''){
        $xml = [System.Xml.Linq.XDocument]::Parse($layoutField.Value)
        $xml.Descendants() | ForEach-Object{
            $current = $_
            $dsAttribute = $current.Attribute('ds');
            if($dsAttribute -and ($dsAttribute -ne $null) -and ($dsAttribute.Value -ne $null) -and ($dsAttribute.Value -ne '') -and (Test-IsGuid $dsAttribute.Value)){
                $oldTarget = Get-Item -Path 'master:' -ID $dsAttribute.Value -ErrorAction SilentlyContinue
                if($oldTarget -and $oldTarget -ne $null){
                    $newPath = Get-NewPath $oldTarget $OldSite $NewSite
                    if($newPath -and $newPath -ne $null -and $newPath -ne ''){
                        $targetItem = Get-Item -path $newPath -ErrorAction SilentlyContinue
                        if($targetItem -and $targetItem -ne $null){
                            $dsAttribute.Value = $targetItem.ID;
                        }
                    }
                }
            }
            $parAttribute = $current.Attribute('par');
            if($parAttribute -and $parAttribute -ne $null){
                $decodedValue = ([System.Web.HttpUtility]::UrlDecode($parAttribute)).Replace('&amp','')
                $decodedValue.Split(';') | ForEach-Object{
                    $param = $_
                    if($param.IndexOf('=') -gt -1){
                        $value = $param.Split('=')[1];
                        if(Test-IsGuid $value){
                            $oldTarget = Get-Item -Path 'master:' -ID $value -ErrorAction SilentlyContinue
                            if($oldTarget -and $oldTarget -ne $null){
                                $newPath = Get-NewPath $oldTarget $OldSite $NewSite
                                if($newPath -and $newPath -ne $null -and $newPath -ne ''){
                                    $targetItem = Get-Item -path $newPath -ErrorAction SilentlyContinue
                                    if($targetItem -and $targetItem -ne $null){
                                        $parAttribute.Value = $parAttribute.Value.Replace($value, $targetItem.ID.ToString())
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Write-Host ('Update layout field {0}' -f $field.Name)
        $layoutField.Value = $xml.ToString();
    }
}

Function Update-LinkField{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Sitecore.Data.Fields.Field]$field,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Item]$OldSite,
        [Parameter(Mandatory = $true, Position = 3)]
        [Item]$NewSite
    )

    $linkField = [Sitecore.Data.Fields.LinkField]$field
    if($linkField.LinkType -eq 'internal'){
        $oldTarget = $linkField.TargetItem
        if($oldTarget -and $oldTarget -ne $null){
            $newPath = Get-NewPath $oldTarget $OldSite $NewSite
            if($newPath -and $newPath -ne $null -and $newPath -ne ''){
                $targetItem = Get-Item -path $newPath -ErrorAction SilentlyContinue
                if($targetItem -and $targetItem -ne $null){
                    $linkField.TargetID = $targetItem.ID;
                    Write-Host ('Update field {0}: {1} --> {2} ' -f $field.Name, $oldTarget.Paths.FullPath, $newPath)
                }
            }
        }
    }
}

Function Update-ReferenceField{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Sitecore.Data.Fields.Field]$Droplink,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Item]$OldSite,
        [Parameter(Mandatory = $true, Position = 3)]
        [Item]$NewSite
    )
    $oldTarget = Get-TargetItem $Droplink
    if($oldTarget -and $oldTarget -ne $null){
        if(Is-Ancestor $oldTarget $OldSite.ID){
            $newPath = Get-NewPath $oldTarget $OldSite $NewSite
            if($newPath -and $newPath -ne $null -and $newPath -ne ''){
                $targetItem = Get-Item -path $newPath -ErrorAction SilentlyContinue
                if($targetItem -and $targetItem -ne $null){
                    $field.Value = $targetItem.ID;
                    Write-Host ('Update field {0}: {1} --> {2} ' -f $field.Name, $oldTarget.Paths.FullPath, $newPath)
                }
            }
        }
    }
}

Function Get-TargetItem{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Sitecore.Data.Fields.Field]$Droplink
    )
    if($Droplink.Value -and $Droplink.Value -ne $null -and $Droplink.Value -ne ''){
        $target = Get-Item -path 'master:' -ID $Droplink.Value -ErrorAction SilentlyContinue
        if($target -and $target -ne $null){
            return $target
        }
    }
    return $null
}

Function Is-Ancestor{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Item]$CurrentItem,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Sitecore.Data.ID]$ItemToCheckId
    )

    $ancestor = $CurrentItem.Axes.GetAncestors()
    return ($ancestor | where { $_.ID -eq $ItemToCheckId }).count -gt 0
}

Function Get-NewPath{
    param(
        [Parameter(Mandatory = $true, Position = 1 )]
        [Item]$CurrentItem,
        [Parameter(Mandatory = $true, Position = 2 )]
        [Item]$OldSite,
        [Parameter(Mandatory = $true, Position = 3)]
        [Item]$NewSite
    )
    $str = '/'
    $CurrentItem.Axes.GetAncestors() | ForEach-Object {
        if($_.ID -eq $OldSite.ID){
            $str += ($NewSite.Name + '/')
        }
        else {
            $str += ($_.Name + '/')
        }
    }
    $str += $CurrentItem.Name
    return $str
}

Function Test-IsGuid
{
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ObjectGuid
    )
    
    [regex]$guidRegex = '(?im)^[{(]?[0-9A-F]{8}[-]?(?:[0-9A-F]{4}[-]?){3}[0-9A-F]{12}[)}]?$'
    return $ObjectGuid -match $guidRegex
}

$currentItem = Get-Item -path '/sitecore/content/Sitecore/Default'
$oldSite = Get-Item -path '/sitecore/content/Sitecore/Storefront'
$newSite = Get-Item -path '/sitecore/content/Sitecore/Default'

Update-Reference -CurrentItem $currentItem -OldSite $oldSite -NewSite $newSite -Exclude @('Catalogs')