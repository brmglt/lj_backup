#!/usr/bin/env bash
#export count=${3:-50}
escape()
{
	sed 's/["\\]/\\\0/g'
}
my_sed()
{
	escape | sed 'N; s/^\(\(events\|prop\)_[0-9]*\)_itemid/id_\1/; s/\n/=/; s/^\([^=]*\)=\(.*\)/\1="\2"/; s/\n/=/;'
}
md5()
{
	md5sum | grep -o '[0-9a-fA-F]\+'
}
login()
{
	local user=$1 password=$2
	eval $(wget -q -O - --post-data "mode=getchallenge&ver=1" $server/interface/flat | my_sed) 
	local response=$(printf "$challenge$(printf %s $password|md5)" |md5)
	export auth="auth_method=challenge&auth_challenge=$challenge&auth_response=$response&user=$user"
	#wget -q -O - --post-data "$auth&mode=login" $server/interface/flat
}


#login $1 $2

backup()
{
	[ ! -d lj_backups ] && mkdir lj_backups
	[ ! -d "lj_backups/$server" ] && mkdir "lj_backups/$server"
	root="lj_backups/$server/${journal:-$user}"
	[ ! -d "$root" ] && mkdir "$root"
	min_date='3000'
	while true; do
		echo wget -q -O - --post-data "$auth&mode=getevents&howmany=$count&selecttype=lastn$beforedate&ver=1$usejournal" $server/interface/flat 
		eval $(wget -q -O - --post-data "$auth&mode=getevents&howmany=$count&selecttype=lastn$beforedate&ver=1$usejournal" $server/interface/flat | my_sed)
		if [ "x$success" != "xOK" ]; then
			echo "Error occured: $errmsg"
			break
		fi
		#break
		if [ "x$events_count" == "x0" ]; then
			echo No more items
			break
		fi
		#echo eventss: ${!events_*}
		unset events_count
		for event in ${!id_events_*}; do
			id=${event/id_events_/}
			eventtime=events_${id}_eventtime
			echo "id=$id, eventtime: ${!eventtime}"
			pre=events_${id}_
			eval "vars=\${!$pre*}"
			for var in $vars; do
				echo ${var#$pre}=\"${!var}\"
			done > "$root/${!eventtime}.sh" 
			[[ -n "${!eventtime}" && "x$min_date" > "x${!eventtime}" ]] && min_date=${!eventtime}
			ln -f "$root/${!eventtime}.sh" "$root/${!event}.ln"
		done
		for prop in ${!id_prop_*}; do
			prop_id=${prop/id_prop_/}
			prop_name=prop_${prop_id}_name
			prop_value=prop_${prop_id}_value
			ln="$root/${!prop}.ln"
			printf %s "prop_${!prop_name}=\"" >> $ln
			printf %s "${!prop_value}" | escape >> $ln
			echo '"' >> $ln
		done
		echo min_date: $min_date
		beforedate="&beforedate=$min_date"
		unset ${!id_events_*}
		unset ${!events_*}
		unset ${!prop_*}
		unset ${!id_prop_*}
		rm $root/*.ln
	done
}
restore()
{
	root=${src_dir:-"lj_backups/$server/$user"}
	ls $root/*.sh | while read item; do
	unset allowmask subject event security ${!prop_*}
	echo Importing item $item...
	eval $(<"$item")
	[ -n "$backdate" ] && prop_opt_backdated=1
	[ -n "$g_security" ] && security=$g_security
	[ -n "$allowmask" ] && allowmask="allowmask=$allowmask&"
	props=$(for prop in ${!prop_*}; do
			printf %s "&${prop/prop_/}=${!prop}"
	done)
	post_data="$auth&mode=postevent&subject=$subject&event=$event&security=$security&$allowmask`date -d "$eventtime" +'year=%Y&mon=%-m&day=%-d&hour=%-H&min=%-M'`$usejournal$props"
	eval $(wget -q -O - --post-data="$post_data" $server/interface/flat | my_sed)
	if [ "x$success" != "xOK" ]; then
		echo "Error occured: $errmsg"
	else
		echo Posted successfully, url=$url
	fi
done
}
delete()
{
	while true; do
		eval $(wget -q -O - --post-data "$auth&mode=getevents&howmany=$count&selecttype=lastn&ver=1&noprops=1&truncate=4$usejournal" $server/interface/flat | my_sed | grep 'url\|id_events\|success\|_count\|errmsg')
		if [ "x$success" != "xOK" ]; then
			echo "Error occured: $errmsg"
			break
		fi
		if [ "x$events_count" == "x0" ]; then
			echo No more items
			break
		fi
		echo itemids: ${!id_events_*}
		unset events_count
		for itemid in ${!id_events_*}; do
			{
				url=${itemid/id_events_/url_}
				#login $1 $2
				echo Deleting url=$url...
				eval $(wget -q -O - --post-data "$auth&security=public&mode=editevent&event=&ver=1&itemid=${!itemid}$usejournal" $server/interface/flat | my_sed)
				if [ "x$success" != "xOK" ]; then
					echo "Error occured: $errmsg when deleting ${!url} (itemid=${itemid})"
				else
					echo "${!url} deleted(itemid=${itemid})"
				fi
			}&
		done
		unset ${!id_events_*}
		echo Waiting for `jobs -p | wc -l` jobs...
		wait `jobs -p`
	done
}
usage()
{
	echo $'Usage: lj_backup.sh backup|restore|delete user password [ -s server -S security -j journal -c count -b -h ]
	-s --server\tLivejournal server to use
	-S --security\tForce all events security to option value
	-j --journal\tUse another journal than user
	-c --count\tFetch count events per one request(may speed up script execution)
	-d --dir\tRestore from directory dir
	-h --help\tPrint this help'	
}
ARGS=`getopt -o "s:c:S:j:d:bh" -l "server:,count:,security:,journal:,dir:,backdate,help" -n "getopt.sh" -- "$@"`
echo 
# A little magic
eval set -- "$ARGS"

# Now go through all the options
while true;
do
  case "$1" in
    -h|--help)
      usage
	  exit 0;;

    -s|--server)
	[ -n "$2" ] && server=$2 
	echo server: $server
      shift 2;;

    -j|--journal)
	[ -n "$2" ] && journal=$2
	echo server: $server
      shift 2;;

    -S|--security)
	[ -n "$2" ] && g_security=$2
	shift 2;;

    -c|--count)
	[ -n "$2" ] && count=$2
	shift 2;;

    -d|--dir)
	[ -n "$2" ] && src_dir=$2
	shift 2;;

	-b|--backdate)
	backdate=1
	shift;;


    --)
      shift
      break;;
	 -*)
	 echo Unknown option $1
	 usage
	 exit -1
  esac
done
echo "$@"
cmd=$1 user=$2 password=$3 count=${count:-10} server=${server:-lj.rossia.org}
auth="user=$user&password=$password"
if [[ "x$journal" != x ]]; then
	usejournal="&usejournal=$journal"
fi
echo cmd=$1 user=$2 password=$3 count=${count:-10} server=${server:-lj.rossia.org}
case $cmd in 
	backup)
	backup;;
	restore)
	restore;;
	delete)
	delete;;
esac
