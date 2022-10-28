#!/bin/bash

# List previews (id, names, and related full image id) that no longer have full image
sql="select tP.fileid, tP.name, tP.fullImgId from (select fileid, name, convert(substring_index(substring_index(path, '/', -2), '/', 1), UNSIGNED) as fullImgId from oc_filecache where path like '%/preview/%.jpg') as tP left join (select fileid from oc_filecache) as tA on tP.fullImgId = tA.fileid where tA.fileid is NULL order by tP.fullImgId"

# Display result and build previews and full images arrays
echo "Previews with no longer present full image:"
pArray=()
fArray=()
fIdCurrent=0

printf "Preview ID\tPreview Name\tFull Img ID\n"
while IFS=$'\t' read pId pName fId;
do
  printf "$pId\t$pName\t$fId\n"
  pArray+=($pId)
  if [ $fId -ne $fIdCurrent ]
  then
    fArray+=($fId)
    fIdCurrent=$fId
  fi
done < <(sudo mysql nextcloud -s -e "$sql")

echo "Found ${#pArray[@]} previews of no longer existing ${#fArray[@]} full images."
if [ ${#pArray[@]} -eq 0 ]; then exit; fi

# Check that these files are absent from bucket
echo "Checking absence of original images in storage..."
# Convert array to string with delimiters, remove last delimiter, add first prefix and brackets
printf -v fList '%s,urn:oid:' "${fArray[@]}"
fList="{urn:oid:${fList::-9}}"
#echo "$fList"
nbFiles=$(rclone ls --include "$fList" SwiftOS:nextcloudbucket | wc -l)
if [ $nbFiles -eq 0 ]
then
  echo "Check ok"
  read -n 1 -r -s -p $'Press any key to proceed to deletion of related previews...\n'
  # Convert array to string with delimiters, remove last delimiter, add first prefix and brackets
  printf -v pListRclone '%s,urn:oid:' "${pArray[@]}"
  printf -v pListSql '%s, ' "${pArray[@]}"
  pListRclone="{urn:oid:${pListRclone::-9}}"
  pListSql="(${pListSql::-2})"
  #echo "$pListRclone"
  #echo "$pListSql"
  echo "Deleting from storage..."
  rclone delete --progress --include "$pListRclone" SwiftOS:nextcloudbucket
  echo "Deleting from database..."
  sudo mysql nextcloud -e "delete from oc_filecache where fileid in $pListSql"
else
  fileList=$(rclone ls --include "$fList" SwiftOS:nextcloudbucket)
  echo "The following files are present in storage. Deletion of previews aborted."
  echo "$fileList"
fi
