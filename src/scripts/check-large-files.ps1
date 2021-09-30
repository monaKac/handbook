[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $BaseRef,

    [Parameter(Mandatory)]
    [number] $PullRequestNumber,

    [Parameter(Mandatory)]
    [SecureString] $GitHubToken
)

$limit = 100KB

$repo = Find-GitRepository

$largeChanges =
  # Get all commits between HEAD and the base ref
  Get-GitCommit -Until $BaseRef |
  # Compare commit to the parent
  ForEach-Object { Compare-GitTree -ReferenceRevision $_.Parents[0].Id -DifferenceRevision $_.Id } |
  # Flatten changes collection
  ForEach-Object { $_ } |
  # Ignore deleted files and files outside the content/ folder
  Where-Object { $_.Status -ne 'Deleted' -and $_.Path -like 'content/*' } |
  # Filter for binary blobs larger than the limit
  Where-Object { $blob = $repo.Lookup($_.Oid); $blob.Size -gt $limit -and $blob.IsBinary }

if ($largeChanges) {
  $existingComment = $repo | Get-GitHubComment -Number $PullRequestNumber | Where-Object { $_.User.type -eq 'Bot' -and $_.Body -match 'large binary files' } | Select-Object -First 1
  $still = if ($existingComment) { 'still' } else { '' }
  $message = (
    "There were $still large binary files (over $($limit / 1KB)KB) detected in this pull request.`n" +
    "To not bloat the size of the Git repository, large binary files, such as pictures and videos, must be uploaded to our [sourcegraph-assets storage](https://console.cloud.google.com/storage/browser/sourcegraph-assets/handbook?project=sourcegraph-dev).`n" +
    "You can do this with drag&drop after following the link. After uploading, use the `"Copy public URL`" button to get a URL you can reference on the handbook page.`n" +
    # TODO: Add link to "Editing the handbook" page once that contains more instructions.
    "`n" +
    "This branch will need to be **rebased** with the binary file completely removed, otherwise the file will still be present in the repository history. @sourcegraph/handbook-support will be happy to help with this.`n" +
    "`n" +
    "The following large binary files $still need to be removed:`n" +
    ($largeChanges | ForEach-Object { "- ``$($_.Path)```n" }) + "`n" +
    "`n" +
    "Thank you! \\(^-^)/"
  )
  $repo | New-GitHubComment -Number $PullRequestNumber -Body $message

  throw $message # fail the GitHub action check
}
