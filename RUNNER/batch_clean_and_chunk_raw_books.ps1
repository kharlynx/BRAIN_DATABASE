$base = "C:\08_DOCUMENTS\BOOK_LIBRARY_ENGINE"
$rawBooksDir = "$base\RAW_BOOKS"
$outputRoot = "$base\RAW_INPUT"

$targetChars = 2200
$minChars = 1760
$maxChars = 2640

if (-not (Test-Path $rawBooksDir)) {
    Write-Host "ERROR: RAW_BOOKS not found: $rawBooksDir"
    exit 1
}

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

Add-Type -AssemblyName System.Web

function Clean-Html-To-Text($htmlPath) {
    $html = Get-Content $htmlPath -Raw -Encoding UTF8

    $html = [regex]::Replace($html, '<script[\s\S]*?</script>', '', 'IgnoreCase')
    $html = [regex]::Replace($html, '<style[\s\S]*?</style>', '', 'IgnoreCase')
    $html = [regex]::Replace($html, '</p>', "`n", 'IgnoreCase')
    $html = [regex]::Replace($html, '<br\s*/?>', "`n", 'IgnoreCase')
    $html = [regex]::Replace($html, '</div>', "`n", 'IgnoreCase')
    $html = [regex]::Replace($html, '</h\d>', "`n", 'IgnoreCase')

    $text = [regex]::Replace($html, '<[^>]+>', '')
    $text = [System.Web.HttpUtility]::HtmlDecode($text)

    $text = $text -replace "`r", ""
    $text = $text -replace "[`t ]+", " "
    $text = $text -replace "`n{2,}", "`n"

    return $text
}

function Split-Text-To-Chunks($text, $outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Remove-Item "$outDir\chunk_*.md" -Force -ErrorAction SilentlyContinue

    $cleanText = ($text -split "`n" | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -ge 8) { $line }
    }) -join ""

    $sentences = @()
    $buffer = ""

    $marks = @(
        [char]0x3002, # 。
        [char]0xFF01, # ！
        [char]0xFF1F, # ？
        [char]0xFF1B, # ；
        [char]0x002E, # .
        [char]0x0021, # !
        [char]0x003F, # ?
        [char]0x003B  # ;
    )

    for ($i = 0; $i -lt $cleanText.Length; $i++) {
        $char = $cleanText[$i]
        $buffer += $char

        if ($marks -contains $char) {
            $sentences += $buffer
            $buffer = ""
        }
    }

    if ($buffer.Trim().Length -gt 0) {
        $sentences += $buffer
    }

    $chunks = @()
    $current = ""

    foreach ($sentence in $sentences) {
        $sentence = $sentence.Trim()
        if ($sentence.Length -eq 0) { continue }

        if (($current.Length + $sentence.Length) -le $maxChars) {
            $current += $sentence
        }
        else {
            if ($current.Length -ge $minChars) {
                $chunks += $current
                $current = $sentence
            }
            else {
                $current += $sentence
            }
        }
    }

    if ($current.Length -gt 0) {
        $chunks += $current
    }

    $index = 1

    foreach ($chunk in $chunks) {
        $fileName = "chunk_{0:D3}.md" -f $index
        $path = Join-Path $outDir $fileName
        Set-Content -Path $path -Value $chunk -Encoding UTF8
        Write-Host "CREATED: $fileName CHARS=$($chunk.Length)"
        $index++
    }

    Write-Host "TOTAL CHUNKS: $($chunks.Count)"
}

$bookDirs = Get-ChildItem $rawBooksDir -Directory | Sort-Object Name

foreach ($bookDir in $bookDirs) {
    Write-Host ""
    Write-Host "=============================="
    Write-Host "PROCESSING BOOK: $($bookDir.Name)"
    Write-Host "=============================="

    $htmlFiles = Get-ChildItem $bookDir.FullName -Filter "*.html" | Sort-Object Name

    if ($htmlFiles.Count -eq 0) {
        Write-Host "SKIP: no html files"
        continue
    }

    $allText = ""

    foreach ($html in $htmlFiles) {
        Write-Host "READ: $($html.Name)"
        $allText += "`n"
        $allText += Clean-Html-To-Text $html.FullName
    }

    $outDir = Join-Path $outputRoot $bookDir.Name
    Split-Text-To-Chunks $allText $outDir

    Write-Host "OUTPUT: $outDir"
}

Write-Host ""
Write-Host "ALL BOOKS DONE"