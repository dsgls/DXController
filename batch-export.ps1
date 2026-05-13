Get-ChildItem -Filter *.u | ForEach-Object {
    $file = $_.Name
    $base = $_.BaseName

    $jobs = @(
        @{ Type='Texture'; Ext='pcx'; Dir='Textures' },
        @{ Type='Sound';   Ext='wav'; Dir='Sounds'   },
    )

    foreach ($j in $jobs) {
        $out = "..\$base\Classes\$($j.Dir)"
        cmd /c "ucc.exe batchexport $file $($j.Type) $($j.Ext) $out"
    }
}
