/// Collect database and license metrics
Class Metrics.Task Extends %SYS.Task.Definition
{

/// 
/// Collects 30 days history of database, disk, and license usage.
/// Runs every hour from the IRIS/Cache Task Scheduler as _SYSTEM and records the highest value throughout the day.
/// To schedule d ##class(Metrics.Task).Schedule(), you can also specify alternative start, stop, and interval times.
/// 
Method OnTask() As %Status
{
	s ^Metrics("SystemMetrics")=$zdatetime($h,3)
	; check database and disk space
	s databaseResults=##class(%ResultSet).%New("%SYS.DatabaseQuery:FreeSpace")
	s status = databaseResults.Execute()
	while (databaseResults.Next()) {
		s database=$zcvt(databaseResults.Data("DatabaseName"),"U")
		i databaseResults.Data("ReadOnly") continue
		s databases(database)=databaseResults.Data("Directory")
		s databases(database,"MaxSize")=..stringToKB(databaseResults.Data("MaxSize"))
		s databases(database,"Size")=..stringToKB(databaseResults.Data("Size"))
		s databases(database,"Available")=..stringToKB(databaseResults.Data("Available"))
		s databases(database,"Used")=databases(database,"Size")-databases(database,"Available")
		s databases(database,"Free")=databaseResults.Data("Free") ; this is a percent value
		s databases(database,"DiskFreeSpace")=..stringToKB(databaseResults.Data("DiskFreeSpace"))
		s databases(database,"DiskSize")=$p(..volumeInfo(..mountvolume(databases(database))),"*",2)
		i +databases(database,"MaxSize")>0 {
			s databases(database,"MaxFree")=$j(((databases(database,"MaxSize")-databases(database,"Used"))/databases(database,"MaxSize"))*100,0,0)
		} else {
			s databases(database,"MaxFree")=$j((databases(database,"DiskFreeSpace")/databases(database,"DiskSize"))*100,0,0)
		}
	}
	
	; build usage history for databases
	s today=+$h
	s database="" for {
		s database=$o(databases(database))
		q:database=""
		s ^Metrics("SystemMetrics","Databases",database)=databases(database)
		i databases(database,"MaxSize")>+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","MaxSize"),-1) s ^Metrics("SystemMetrics","Databases",database,today,"usage","MaxSize")=databases(database,"MaxSize")
		i databases(database,"Size")>+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","Size")) s ^Metrics("SystemMetrics","Databases",database,today,"usage","Size")=databases(database,"Size")
		i databases(database,"Available")<+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","Available"),9999999999999999) s ^Metrics("SystemMetrics","Databases",database,today,"usage","Available")=databases(database,"Available")
		i databases(database,"Used")>+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","Used")) s ^Metrics("SystemMetrics","Databases",database,today,"usage","Used")=databases(database,"Used")
		i databases(database,"Free")<+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","Free"),9999999999999999) s ^Metrics("SystemMetrics","Databases",database,today,"usage","Free")=databases(database,"Free")
		i databases(database,"MaxFree")<+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","MaxFree"),9999999999999999) s ^Metrics("SystemMetrics","Databases",database,today,"usage","MaxFree")=databases(database,"MaxFree")
		i databases(database,"DiskFreeSpace")<+$g(^Metrics("SystemMetrics","Databases",database,today,"usage","DiskFreeSpace"),9999999999999999) s ^Metrics("SystemMetrics","Databases",database,today,"usage","DiskFreeSpace")=databases(database,"DiskFreeSpace")
		i databases(database,"DiskSize")'=$g(^Metrics("SystemMetrics","Databases",database,today,"usage","DiskSize")) s ^Metrics("SystemMetrics","Databases",database,today,"usage","DiskSize")=databases(database,"DiskSize")
		
		;remove entries over 30 days old
		s chk=today-30
		for {
			s chk=$o(^Metrics("SystemMetrics","Databases",database,chk),-1)
			q:chk=""
			k ^Metrics("SystemMetrics","Databases",database,chk)
		}
	}
	
	; check license usage
	I ##CLASS(%SYSTEM.Version).GetMajor()<2008 S license("Total")=$SYSTEM.License.KeyLicenseUnits()
	I ##CLASS(%SYSTEM.Version).GetMajor()>2007 s license("Total")=$SYSTEM.License.GetUserLimit()
	S license("Available")=##class(%SYSTEM.License).LUAvailable()
	S license("Used")=##class(%SYSTEM.License).LUConsumed()
	S license("Customer")=##class(%SYSTEM.License).KeyCustomerName()
	S license("Expires")=##class(%SYSTEM.License).KeyExpirationDate()
	s license("IsMulti")=$s(##class(%SYSTEM.License).KeyServer()["Multi":1,1:0)
	; there are quirks when Intersystems issue temporary licenses increases that mess these values so deal with it.
	I (license("Available")+license("Used"))>license("Total") s license("Total")=license("Available")+license("Used")
	
	s ^Metrics("SystemMetrics","License",today,"Customer")=license("Customer")
	s ^Metrics("SystemMetrics","License",today,"IsMultiServer")=license("IsMulti")
	s ^Metrics("SystemMetrics","License",today,"Expires")=license("Expires")
	s ^Metrics("SystemMetrics","License",today,"Total")=license("Total")
	i license("Available")<+$g(^Metrics("SystemMetrics","License",today,"Available"),99999999) s ^Metrics("SystemMetrics","License",today,"Available")=license("Available")
	i license("Used")>+$g(^Metrics("SystemMetrics","License",today,"Used")) s ^Metrics("SystemMetrics","License",today,"Used")=license("Used")
	
	;remove entries over 30 days old
	s chk=today-30
	for {
		s chk=$o(^Metrics("SystemMetrics","License",chk),-1)
		q:chk=""
		k ^Metrics("SystemMetrics","License",chk)
	}
	return $$$OK
}

/// returns the mounted volume for the directory supplied
Method mountvolume(dir)
{
	q:($g(dir)="") -999
	s io=$io
	S slash=$e($zu(168),*)
	s command="printf ""%s\n"" `df -Pk "_dir_"` 2>/dev/null"
	i $ZUTIL(68,40,1)
	i slash="\" s command="mountvol "_dir_" /L"
	s err=""
	TRY {
		o command:"Q":10 i '$t s err=-1
		u command for {r data q:$zeof  s data($i(i))=data}
		c command
	} CATCH { s err=-2 }
	i err'="" q err
	i slash="\" {
		s mountvolume=$g(data(1))
		s drive=$P(dir,":")_":\"
		i $zcvt(mountvolume,"l")["not a reparse point" s mountvolume=$zcvt(drive,"U")
		i $zcvt(mountvolume,"l")["not mounted" s mountvolume=$zcvt(drive,"U")
		i $zcvt(mountvolume,"l")["system cannot find" s mountvolume=$zcvt(drive,"U")
		i $zcvt(mountvolume,"l")["or lists a volume mount point" s mountvolume=$zcvt(drive,"U")
		s mountvolume=$zstrip(mountvolume,"<>W")
	} else {
		s mountvolume=$g(data(8),-2)
	}
	i mountvolume="" s mountvolume=-3
	i mountvolume'[slash s mountvolume=-4
	u io
	return mountvolume
}

/// get size and freespace for a volume
Method volumeInfo(volume)
{
	s slash=$e($zu(168),*),mountInfo=""
	i slash="\" {
		s volume=$p(volume,"\")
		i volume'?1A1":" q -1
		s command="wmic logicaldisk "_volume_" get size,freespace"
		TRY {
			o command:"Q":10 i '$t s err=-1
			u command for {r data q:$zeof  s data($i(i))=data}
			c command
		} CATCH { s err=-2 }
		s mountInfo=$s($g(err)<0:err,1:$replace($g(data(3)),"  ","*"))
		s $p(mountInfo,"*")=$p(mountInfo,"*")\1024
		s $p(mountInfo,"*",2)=$p(mountInfo,"*",2)\1024
	} else {
		s command="df -k "_volume
		TRY {
			o command:"Q":10 i '$t s err=-1
			u command for {r data q:$zeof  s data($i(i))=data}
			c command
		} CATCH { s err=-3 }
		i $g(err)<0 {
			s mountInfo=err
		} else{
			s mountInfo=$replace($replace($g(data(2)),"  ","*")," ","*")
			s mountInfo=$p(mountInfo,"*",5)_"*"_$p(mountInfo,"*",4)
		}
	}
	q mountInfo
}

Method stringToKB(value) As %Numeric
{
	f i=$l(value):-1:1 q:$e(value,i)?1N
	s num=$e(value,1,i),ident=$zstrip($zcvt($e(value,i+1,*),"U"),"<>W")
	s num=num*$s(ident="MB":1024,ident="GB":(1024*1024),ident="TB":(1024*1024*1024),1:1)
	return num
}

ClassMethod Schedule(startTime As %Time = {"00:00"}, stopTime As %Time = {"23:59"}, intervalMinutes As %SmallInt = 60) As %Status
{
	; remove any existing tasks
	i ..DeleteSchedule()
	;
	; create a backup task for a full backup of the database list
	s backupTask=##class(%SYS.Task).%New()
	s backupTask.NameSpace=$znspace
	s backupTask.Name="SystemMetrics"
	s backupTask.TaskClass="Metrics.Task"
	s backupTask.Description="System Metrics"
	s backupTask.RunAsUser="_SYSTEM"
	s backupTask.TimePeriod=0
	s backupTask.DailyFrequency=1
	s backupTask.DailyFrequencyTime=0
	s backupTask.DailyStartTime=$ztimeh(startTime)
	s backupTask.DailyEndTime=$ztimeh(stopTime)
	s backupTask.DailyIncrement=intervalMinutes
	s backupTask.SuspendOnError=0
	s backupTask.RescheduleOnStart=1
	s status=backupTask.%Save()
	q status
}

ClassMethod DeleteSchedule() As %Status
{
	s status=$$$OK
	s taskM=##class(%SYS.Task).%New()
	s purgeID=##class(%SYS.Task).FindId("SystemMetrics")
	s status=taskM.%DeleteId(purgeID)
	q status
}

}
