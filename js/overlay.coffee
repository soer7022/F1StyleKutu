window.app = angular.module 'app', [
    'ngAnimate'
    'ngSanitize'
]

app.config ($locationProvider) ->
    $locationProvider.hashPrefix ''

app.service 'config', ($location) ->
    vars = $location.search()

    fps = parseInt(vars.fps) or 10
    fps = Math.max 1, Math.min 60, fps

    host: vars.host or '127.0.0.1:8182'
    fps: fps
    showTyres: !!vars.showTyres
    # standings
    standingsMaxRows: parseInt(vars.standingsMaxRows) or 20
    standingsWindow: parseInt(vars.standingsWindow) or 5
    standingsMulticlass: vars.standingsMulticlass != 'false'
    # relatives
    relativesCompact: vars.relativesCompact == 'true'
    # car
    carFuel: vars.carFuel != 'false'
    carTemps: vars.carTemps != 'false'
    carWind: vars.carWind == 'true'
    carWeatherSOF: vars.carWeatherSOF == 'true'
    # twitch
    twitchChannel: vars.twitchChannel
    twitchNewFollowerTmpl: if vars.twitchNewFollowerTmpl? then vars.twitchNewFollowerTmpl \
        else 'All HAIL new follower: <b>{0}</b>'
    twitchNewFollowerTimeout: vars.twitchNewFollowerTimeout or 10
    record: vars.record

app.service 'iRData', ($rootScope, config) ->
    requestParams = [
        # yaml
        'DriverInfo'
        'SessionInfo'

        # telemetry
        'CamCarIdx'
        # 'CarIdxEstTime'
        # 'CarIdxGear'
        'CarIdxLap'
        'CarIdxLapDistPct'
        'CarIdxOnPitRoad'
        # 'CarIdxRPM'
        'CarIdxTrackSurface'
        'DisplayUnits'
        'FuelLevel'
        # 'Gear'
        'IsOnTrack'
        'IsOnTrackCar'
        'IsReplayPlaying'
        # 'Lap'
        # 'LapDist'
        'LapDistPct'
        'LFwearR'
        'OilTemp'
        'OnPitRoad'
        'PlayerCarIdx'
        'PlayerCarTeamIncidentCount'
        'PlayerTrackSurface'
        'RadioTransmitCarIdx'
        # 'ReplayFrameNum'
        'ReplayFrameNumEnd'
        # 'RPM'
        'SessionFlags'
        'SessionNum'
        'SessionState'
        'SessionTime'
        'SessionTimeRemain'
        # 'Speed'
        'WaterTemp'
    ]

    if config.carWind
        requestParams.push(
            'WindDir'
            'WindVel'
            'YawNorth'
        )

    if config.carWeatherSOF
        requestParams.push(
            'TrackTempCrew'
        )

    if config.showTyres
        requestParams.push(
            # ibt
            'LFtempL'
            'LFtempM'
            'LFtempR'
            'RFtempL'
            'RFtempM'
            'RFtempR'
            'LRtempL'
            'LRtempM'
            'LRtempR'
            'RRtempL'
            'RRtempM'
            'RRtempR'
            'LFpressure'
            'RFpressure'
            'LRpressure'
            'RRpressure'
        )

    ir = new IRacing \
        # request params
        requestParams,
        # request params once
        [
            # yaml
            'QualifyResultsInfo'
            # 'SplitTimeInfo'
            'WeekendInfo'
        ],
        config.fps,
        config.host,
        config.showTyres,
        config.record

    ir.onConnect = (update=true) ->
        ir.data.connected = true
        if update
            $rootScope.$apply()
            if ir.record
                ir.playRecord 350, null, 10

    ir.onDisconnect = (update=true) ->
        ir.data.connected = false
        if update
            $rootScope.$apply()

    ir.onUpdate = (keys) ->
        # console.log keys
        if 'DriverInfo' in keys
            updateDriversByCarIdx()
            updateCarClassIDs()
        if 'SessionInfo' in keys
            updatePositionsByCarIdx()
            updateQualifyResultsByCarIdx()
        if 'QualifyResultsInfo' in keys
            updateQualifyResultsByCarIdx()
        # test
        # ir.data.CamCarIdx = 3
        $rootScope.$apply()

    updateDriversByCarIdx = ->
        ir.data.DriversByCarIdx ?= {}
        for driver in ir.data.DriverInfo.Drivers
            ir.data.DriversByCarIdx[driver.CarIdx] = driver

    updateCarClassIDs = ->
        for driver in ir.data.DriverInfo.Drivers
            carClassId = driver.CarClassID
            ir.data.CarClassIDs ?= []
            if driver.UserID != -1 and driver.IsSpectator == 0 and carClassId not in ir.data.CarClassIDs
                ir.data.CarClassIDs.push carClassId

    updatePositionsByCarIdx = ->
        ir.data.PositionsByCarIdx ?= []
        for session, i in ir.data.SessionInfo.Sessions
            while i >= ir.data.PositionsByCarIdx.length
                ir.data.PositionsByCarIdx.push {}
            if session.ResultsPositions
                for position in session.ResultsPositions
                    ir.data.PositionsByCarIdx[i][position.CarIdx] = position

    updateQualifyResultsByCarIdx = ->
        ir.data.QualifyResultsByCarIdx ?= {}
        results = ir.data.QualifyResultsInfo?.Results or ir.data.SessionInfo.Sessions[ir.data.SessionNum]?.QualifyPositions or []
        for position in results
            ir.data.QualifyResultsByCarIdx[position.CarIdx] = position

    return ir.data





# app.controller 'MainCtrl', ($scope, iRData) ->
#     $scope.ir = iRData

#          _______.___________.    ___      .__   __.  _______   __  .__   __.   _______      _______.
#         /       |           |   /   \     |  \ |  | |       \ |  | |  \ |  |  /  _____|    /       |
#        |   (----`---|  |----`  /  ^  \    |   \|  | |  .--.  ||  | |   \|  | |  |  __     |   (----`
#         \   \       |  |      /  /_\  \   |  . `  | |  |  |  ||  | |  . `  | |  | |_ |     \   \
#     .----)   |      |  |     /  _____  \  |  |\   | |  '--'  ||  | |  |\   | |  |__| | .----)   |
#     |_______/       |__|    /__/     \__\ |__| \__| |_______/ |__| |__| \__|  \______| |_______/
#

app.controller 'StandingsCtrl', ($scope, $element, config, iRData) ->
    ir = $scope.ir = iRData
    carIdx = null

    $scope.$watch 'ir.connected', (n, o) ->
        $element.toggleClass 'ng-hide', not n
        # console.log ir
    $scope.formatName = (name)->
        n = name.split(" ");
        return n[n.length - 1].slice(0, 3).toUpperCase();


    # test
    # $scope.$watch 'ir.SessionNum', (n, o) ->
    #     console.log ir.SessionNum
    # $scope.$watch 'ir.SessionInfo', (n, o) ->
    #     console.log ir.SessionInfo
    #     # console.log ir.SessionInfo
    # $scope.$watch 'ir.QualifyResultsInfo', (n, o) ->
    #     console.log ir.QualifyResultsInfo

    $scope.$watch 'ir.CamCarIdx', (n, o) ->
        carIdx = n
        updateStandings()

    updateStandings = ->
        if not ir.SessionInfo or not (ir.SessionNum >= 0)
            return
        session = ir.SessionInfo.Sessions[ir.SessionNum]
        standings = session.ResultsPositions or []
        if not standings.length and (ir.QualifyResultsInfo or session.QualifyPositions)
            $scope.standingsType = 'QualifyResults'
            standings = ir.QualifyResultsInfo?.Results or session.QualifyPositions
        else
            $scope.standingsType = session.SessionType

        # filter standings if show only my class
        if ir.CarClassIDs and ir.CarClassIDs.length > 1 and not config.standingsMulticlass
            myClassId = ir.DriversByCarIdx[carIdx].CarClassID
            standings = standings.filter (item) ->
                myClassId == ir.DriversByCarIdx[item.CarIdx].CarClassID

        $scope.standingsOriginal = standings.slice()
        if not standings.length
            $scope.standings = standings
            return
        maxRows = config.standingsMaxRows
        curCarWindow = config.standingsWindow
        curCarWindowHalf = curCarWindow / 2 | 0
        curCarIndex = -1
        # find index in standings of current cam car idx
        for s, i in standings
            if s.CarIdx == carIdx
                curCarIndex = i
                break
        if standings.length > maxRows
            if curCarIndex == -1 or curCarIndex < maxRows - curCarWindowHalf
                standings = standings[...maxRows]
            else
                standings = \
                    standings[...maxRows - 1 - curCarWindow + Math.max(0, curCarWindowHalf + curCarIndex + 1 - standings.length)].concat \
                    null,
                    standings[curCarIndex - curCarWindowHalf ... curCarIndex + Math.ceil(curCarWindow / 2)]
        $scope.standings = standings
        # test
        # if not testInterval?
        #     testInterval = setInterval ->
        #         r1 = 1 + Math.random() * (standings.length - 3) | 0
        #         r2 = r1 + (if Math.random() > .5 then 1 else -1) | 0
        #         r1 = 2
        #         r2 = 8
        #         [standings[r1], standings[r2]] = [standings[r2], standings[r1]]
        #     , 1000

    $scope.$watch 'ir.SessionInfo', updateStandings
    $scope.$watch 'ir.SessionNum', updateStandings
    $scope.$watch 'ir.QualifyResultsInfo', updateStandings

    # test
    # testInterval = null
    # setInterval ->
    #     # r1 = 1 + Math.random() * (standings.length - 3) | 0
    #     # r2 = r1 + (if Math.random() > .5 then 1 else -1) | 0
    #     r1 = 4
    #     r2 = 8
    #     results = ir.SessionInfo.Sessions[ir.SessionNum].ResultsPositions
    #     [results[r1].Position, results[r2].Position] = [results[r2].Position, results[r1].Position]
    #     [results[r1], results[r2]] = [results[r2], results[r1]]
    #     ir.SessionInfo = angular.copy(ir.SessionInfo)
    #     $scope.$apply()
    # , 3000

app.directive 'appStandingsRow', ($animate, $timeout, config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsRow, (n, o) ->
            carIdx = n
            lastPosition = null
            element.toggleClass 'divider', not (carIdx >= 0)

        scope.$watch 'ir.CamCarIdx', (n, o) ->
            element.toggleClass 'current', carIdx == n

        lastPosition = null
        gainUpTimeout = null
        gainDownTimeout = null

        scope.$watch 'ir.SessionNum', resetLastPosition = ->
            lastPosition = null

        scope.$watch 'ir.SessionInfo', checkGainPosition = ->
            if not carIdx?
                return

            position = if config.standingsMulticlass then scope.i.Position else scope.i.ClassPosition
            if not lastPosition?
                null
            else if position < lastPosition
                $timeout.cancel gainUpTimeout
                $timeout.cancel gainDownTimeout
                element.removeClass 'gain-up gain-down'

                gainUpTimeout = $timeout ->
                    element.addClass 'gain-up'
                    gainUpTimeout = $timeout ->
                        element.removeClass 'gain-up'
                    , 50
                , 50
            else if position > lastPosition
                $timeout.cancel gainUpTimeout
                $timeout.cancel gainDownTimeout
                element.removeClass 'gain-up gain-down'

                gainDownTimeout = $timeout ->
                    element.addClass 'gain-down'
                    gainDownTimeout = $timeout ->
                        element.removeClass 'gain-down'
                    , 50
                , 50

            lastPosition = position

        scope.$on '$destroy', ->
            $timeout.cancel gainUpTimeout
            $timeout.cancel gainDownTimeout

app.directive 'appStandingsPosition', (config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsPosition, (n, o) ->
            carIdx = n
            updateStandingsPosition()

        updateStandingsPosition = ->
            if not carIdx?
                return
            isQualifyResults = scope.$parent.standingsType == 'QualifyResults'
            position = scope.i
            pos = if config.standingsMulticlass then position.Position else position.ClassPosition
            if not config.standingsMulticlass or isQualifyResults
                pos += 1
            element.text pos

        scope.$watch 'ir.SessionInfo', updateStandingsPosition
        scope.$watch 'ir.SessionNum', updateStandingsPosition

app.directive 'appStandingsGain', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsGain, (n, o) ->
            carIdx = n
            updateStandingsGain()

        updateStandingsGain = ->
            if not ir.QualifyResultsByCarIdx or \
                    not ir.SessionInfo or \
                    scope.$parent.standingsType != 'Race'
                element.addClass 'ng-hide'
                return
            element.removeClass 'ng-hide'
            if not carIdx?
                element.text ''
                return
            position = scope.i
            gain = ir.QualifyResultsByCarIdx[carIdx].ClassPosition - position.ClassPosition
            if gain == 0
                element.text ''
            else
                element.toggleClass 'gain-up', gain > 0
                element.toggleClass 'gain-down', gain < 0
                element.text (if gain > 0 then '+' else '') + gain

        scope.$watch 'ir.SessionInfo', updateStandingsGain
        scope.$watch 'ir.SessionNum', updateStandingsGain
        scope.$watch 'ir.QualifyResultsInfo', updateStandingsGain

app.directive 'appStandingsClassPosition', (config, iRData) ->
    link: (scope, element, attrs) ->
        if not config.standingsMulticlass
            element.addClass 'ng-hide'
            return

        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsClassPosition, (n, o) ->
            carIdx = n
            updateStandingsClassPosition()

        updateStandingsClassPosition = ->
            if not ir.CarClassIDs or ir.CarClassIDs.length < 2
                element.addClass 'ng-hide'
                return

            if not (carIdx >= 0) or not ir.DriversByCarIdx or \
                    carIdx not of ir.DriversByCarIdx
                return

            position = scope.i
            driver = ir.DriversByCarIdx[carIdx]
            carClassColor = driver.CarClassColor
            if carClassColor == 0xffffff
                carClassColor = 0xffda59
            if carClassColor == 0
                carClassId = driver.CarClassID
                for d in ir.DriverInfo.Drivers
                    if d.CarClassID == carClassId and d.CarClassColor
                        carClassColor = d.CarClassColor

            element.removeClass 'ng-hide'
            element.text position.ClassPosition + 1
            element.css
                background: "rgba(#{carClassColor >> 16},\
                    #{carClassColor >> 8 & 0xff},\
                    #{carClassColor & 0xff},\
                    .75)"

        scope.$watch 'ir.SessionInfo', updateStandingsClassPosition
        scope.$watch 'ir.SessionNum', updateStandingsClassPosition

app.directive 'appCarNumber', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null
        colors = ['#2AB4A5','#C30000', '#00007D', '#FFFFFF','#FF5F0F','#0000FF','#808080', '#6C0000','#FFD800', '#323232', '#006EFF']

        scope.$watch attrs.appCarNumber, (n, o) ->
            carIdx = n
            updateCarNumber()

        updateCarNumber = ->
            if not carIdx? or not ir.DriversByCarIdx? or carIdx not of ir.DriversByCarIdx
                element.text ''
                return
            driver = ir.DriversByCarIdx[carIdx]
            carClassColor = driver.CarClassColor
            if carClassColor == 0xffffff
                carClassColor = 0xffda59
            if carClassColor == 0
                carClassId = driver.CarClassID
                for d in ir.DriverInfo.Drivers
                    if d.CarClassID == carClassId and d.CarClassColor
                        carClassColor = d.CarClassColor

            element.css
                background: colors[driver.CarNumber %% colors.length]

        scope.$watch 'ir.DriverInfo', updateCarNumber

app.directive 'appCarImage', (config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appCarImage, (n, o) ->
            carIdx = n
            updateCarImage()

        convertColorToHex = (color) ->
            out = color.toString 16
            while out.length < 6 then out = "0#{out}"
            out

        updateCarImage = ->
            if not carIdx? or not ir.DriversByCarIdx? or carIdx not of ir.DriversByCarIdx
                element.addClass 'ng-hide'
                element.css
                    'background-image': 'none'
                return
            element.removeClass 'ng-hide'
            driver = ir.DriversByCarIdx[carIdx]
            wheelColor = driver.CarDesignStr.match(/(?:.*?[,;]){4}(.*)/i)?[1]
            if wheelColor
                wheelColorType = if driver.CarDesignStr.search(';') == -1 then 0 else 1
                wheelColorStr = "#{wheelColorType},#{wheelColor}"

            carImage = "http://#{config.host}/proxy/ir/car.png\
                ?dirpath=#{driver.CarPath.split(' ').join '\\\\'}\
                &size=0\
                &pat=#{driver.CarDesignStr.match(/\d+/)[0]}\
                &numberslant=#{driver.CarNumberDesignStr.match(/,(\d+),/)?[1] or 0}\
                &lic=#{convertColorToHex driver.LicColor}\
                &colors=#{driver.CarDesignStr.match(/,((?:[\da-f]+,?){2}(?:[\da-f]+))/i)[1]}\
                &sponsors=#{driver.CarSponsor_1},#{driver.CarSponsor_2}\
                &numfont=#{driver.CarNumberDesignStr.match(/\d+/)[0]}\
                &numcolors=#{driver.CarNumberDesignStr.match(/(?:[\da-f]+,?){3}$/i)[0]}\
                &car_number=#{driver.CarNumber}\
                &wheels=#{if wheelColorStr? then wheelColorStr else ''}
                "
            console.log carImage
            # http://127.0.0.1:32034/car.png?dirpath=v8supercars\holden2014&size=2&pat=4&numberslant=2&lic=0153db&colors=FFFFFF,ED2129,2A3795&sponsors=36,81&numfont=1&numcolors=FFFFFF,ED2129,2A3795&club=46&car_number=82&wheels=0,c0c229

            # bug http://127.0.0.1:8182/proxy/ir/car.png?dirpath=v8supercars\holden2014&size=0&pat=1&numberslant=0&lic=&colors=fb0e19,ffffff,000000&sponsors=1,0&numfont=0&numcolors=ffffff,777777,000000&car_number=10&wheels=
            element.css
                'background-image': "url(#{carImage})"

        scope.$watch 'ir.DriverInfo', updateCarImage

app.directive 'appStandingsGap', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsGap, (n, o) ->
            carIdx = n
            updateStandingsGap()

        updateStandingsGap = ->
            if not carIdx? or not ir.SessionInfo
                element.addClass 'ng-hide'
                return

            standings = scope.$parent.standingsOriginal
            standingsType = scope.$parent.standingsType
            isRace = standingsType == 'Race'
            firstPosition = standings[0]
            position = scope.i

            #element.toggleClass 'ng-hide', isRace and firstPosition.LapsComplete == 0

            if firstPosition.CarIdx == carIdx
                element.text if isRace then 'Interval' else timeFormat firstPosition.FastestTime,3
                return

            if isRace
                gap = position.Time - firstPosition.Time
            else
                gap = if position.FastestTime > 0 then position.FastestTime - firstPosition.FastestTime else -1

            if isRace
                diffLaps = firstPosition.LapsComplete - position.LapsComplete
                if gap >= 0 and position.LapsComplete
                    if diffLaps <= 0 or \
                            (diffLaps == 1 and (firstPosition.LastTime == -1 or gap < firstPosition.LastTime))
                        element.text "+" + timeFormat gap, 3
                    else if ir.SessionState < 5 and diffLaps > 0 and firstPosition.LastTime != -1 and \
                            Math.ceil(gap / firstPosition.LastTime) == diffLaps
                        element.text "+" + "#{diffLaps - 1}L"
                    else if diffLaps > 0
                        element.text "+" + "#{diffLaps}L"
                else if diffLaps > 1
                    element.text "+" + "#{diffLaps}L"
                else
                    element.text 'Interval'
            else
                if gap >= 0
                    element.text '+' + timeFormat gap, 3
                else
                    element.text 'Interval'

        scope.$watch 'ir.SessionInfo', updateStandingsGap
        scope.$watch 'ir.SessionNum', updateStandingsGap

app.directive 'appStandingsInt', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsInt, (n, o) ->
            carIdx = n
            updateStandingsInt()

        updateStandingsInt = ->
            carIdx = scope.$eval attrs.appStandingsInt
            if not carIdx? or not ir.SessionInfo
                element.addClass 'ng-hide'
                return
            standings = scope.$parent.standingsOriginal
            standingsType = scope.$parent.standingsType
            isRace = standingsType == 'Race'
            firstPosition = standings[0]
            position = scope.i

            element.toggleClass 'ng-hide', isRace and firstPosition.LapsComplete == 0

            if firstPosition.CarIdx == carIdx
                element.text if isRace then position.LapsComplete else ''
                return

            prevPosition = standings[standings.indexOf(position) - 1]
            if isRace
                interval = position.Time - prevPosition.Time
            else
                interval = if position.FastestTime > 0 and prevPosition.FastestTime > 0 \
                    then position.FastestTime - prevPosition.FastestTime else -1

            if isRace
                diffLaps = prevPosition.LapsComplete - position.LapsComplete
                if interval >= 0 and position.LapsComplete
                    if diffLaps <= 0 or \
                            (diffLaps == 1 and (firstPosition.LastTime == -1 or interval < firstPosition.LastTime))
                        element.text timeFormat interval, 1
                    else if ir.SessionState < 5 and diffLaps > 0 and firstPosition.LastTime != -1 and \
                            Math.ceil(interval / firstPosition.LastTime) == diffLaps
                        element.text "#{diffLaps - 1}L"
                    else if diffLaps > 0
                        element.text "#{diffLaps}L"
                else if diffLaps > 1
                    element.text "#{diffLaps}L"
                else
                    element.text 'Interval'
            else
                if interval >= 0
                    element.text timeFormat interval, 3
                else
                    element.text 'Interval'

        scope.$watch 'ir.SessionInfo', updateStandingsInt
        scope.$watch 'ir.SessionNum', updateStandingsInt

app.directive 'appStandingsLapTime', ($interval, $timeout, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null
        lastLapsComplete = null
        lastLapTime = null
        newLapTimeout = null

        scope.$watch attrs.appStandingsLapTime, (n, o) ->
            carIdx = n
            updateStandingsLapTime()

        updateStandingsLapTime = ->
            if not carIdx? or not ir.SessionInfo or not (ir.SessionNum >= 0) or not ir.PositionsByCarIdx
                return
            standings = scope.$parent.standingsOriginal
            standingsType = scope.$parent.standingsType
            isRace = standingsType == 'Race'
            position = scope.i

            if not lastLapsComplete?
                lastLapsComplete = position.LapsComplete

            if isRace
                lapTime = position.LastTime
                element.removeClass 'ng-hide pb best'
                if lapTime > 0
                    lapTime = Math.floor(lapTime * 1000) / 1000
                    element.text timeFormat lapTime
                    fastestLap = ir.SessionInfo.Sessions[ir.SessionNum].ResultsFastestLap[0]
                    if carIdx == fastestLap.CarIdx and position.LapsComplete == fastestLap.FastestLap
                        element.addClass 'best'
                    else if position.LapsComplete == position.FastestLap
                        element.addClass 'pb'

                    if lastLapsComplete < position.LapsComplete
                        lastLapsComplete = position.LapsComplete
                        element.addClass 'new-lap'
                        $timeout ->
                            element.removeClass 'new-lap'
                        , 100
                    # test
                    # $interval ->
                    #     element.addClass 'new-lap'
                    #     $timeout ->
                    #         element.removeClass 'new-lap'
                    #     , 100
                    # , 7000
                else
                    element.addClass 'ng-hide'
            else
                element.removeClass 'ng-hide pb best'
                lapTime = position.FastestTime
                if lapTime > 0
                    lapTime = Math.floor(lapTime * 1000) / 1000
                    element.text timeFormat lapTime
                    if not lastLapTime? or lastLapTime > lapTime
                        lastLapTime = lapTime
                        element.addClass 'new-lap'
                        $timeout ->
                            element.removeClass 'new-lap'
                        , 100
                else
                    element.addClass 'ng-hide'

        scope.$watch 'ir.SessionInfo', updateStandingsLapTime
        scope.$watch 'ir.SessionNum', updateStandingsLapTime

        scope.$watch 'ir.SessionNum', ->
            lastLapsComplete = lastLapTime = null

        scope.$on '$destroy', ->
            $timeout.cancel newLapTimeout

app.directive 'appStandingsIncidents', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appStandingsIncidents, (n, o) ->
            carIdx = n
            updateStandingsIncidents()

        updateStandingsIncidents = ->
            position = scope.i
            if position
                incidents = position.Incidents
                if not (incidents > 0) and ir.PlayerCarIdx == position.CarIdx
                    incidents = ir.PlayerCarTeamIncidentCount
            element.toggleClass 'ng-hide', not (incidents > 0)
            element.text "#{incidents}x"

        scope.$watch 'ir.SessionInfo', updateStandingsIncidents
        scope.$watch 'ir.SessionNum', updateStandingsIncidents
        scope.$watch 'ir.PlayerCarTeamIncidentCount', updateStandingsIncidents

#          _______. _______     _______.     _______. __    ______   .__   __.
#         /       ||   ____|   /       |    /       ||  |  /  __  \  |  \ |  |
#        |   (----`|  |__     |   (----`   |   (----`|  | |  |  |  | |   \|  |
#         \   \    |   __|     \   \        \   \    |  | |  |  |  | |  . `  |
#     .----)   |   |  |____.----)   |   .----)   |   |  | |  `--'  | |  |\   |
#     |_______/    |_______|_______/    |_______/    |__|  \______/  |__| \__|
#

app.controller 'SessionCtrl', ($scope, $element, iRData) ->
    $scope.ir = iRData

app.directive 'appSessionLap', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null
        sessionLaps = null
        carIdxLapWatcher = null
        maxLapTimes = 5
        avgLapTimes = {}

        scope.$watch 'ir.CamCarIdx', (n, o) ->
            sessionLaps = null
            carIdx = n
            carIdxLapWatcher?()
            carIdxLapWatcher = scope.$watch "ir.CarIdxLap[#{carIdx}]", updateSessionLap
            updateSessionLaps()

        updateSessionLap = ->
            if not (carIdx >= 0) or not ir.CarIdxLap
                element.text '0'
                return
            lap = ir.CarIdxLap[carIdx]
            element.html "#{lap}" + (if sessionLaps then "/#{sessionLaps}" else '')

        updateSessionLaps = ->
            if not ir.SessionInfo or not (ir.SessionNum >= 0) or \
                    not ir.DriversByCarIdx? or carIdx not of ir.DriversByCarIdx
                sessionLaps = null
                return
            updateAvgLapTimes()
            session = ir.SessionInfo.Sessions[ir.SessionNum]
            newSessionLaps = session.SessionLaps
            if newSessionLaps > 0
                sessionLaps = newSessionLaps
            if session.SessionType == 'Race'
                carClass = ir.DriversByCarIdx[carIdx].CarClassID
                lapsComplete = avgLapTimes[carClass]?.lapsComplete
                if not lapsComplete? or lapsComplete < 2
                    raceLaps = parseInt(session.SessionLaps) or null
                    avgSessionLaps = null
                    raceSessionTime = parseInt session.SessionTime
                    if raceSessionTime > 0
                        results = ir.QualifyResultsInfo?.Results or session.QualifyPositions
                        if not results?
                            for s in ir.SessionInfo.Sessions
                                if s.SessionType.search(/qual/i) != -1
                                    if s.ResultsPositions
                                        results = s.ResultsPositions
                                        break
                                else if s.SessionType.search(/race/i) == -1 # not race
                                    results = s.ResultsPositions
                        if results?
                            for p in results
                                if p.Position == 0 and p.FastestTime > 0
                                    firstClassLapTime = p.FastestTime
                                if p.ClassPosition == 0 and p.FastestTime > 0 and ir.DriversByCarIdx[p.CarIdx].CarClassID == carClass
                                    if p.Position != 0 and firstClassLapTime > 0
                                        avgSessionLaps = Math.ceil(raceSessionTime / firstClassLapTime) * firstClassLapTime / p.FastestTime
                                    else
                                        avgSessionLaps = raceSessionTime / p.FastestTime
                                    break
                    if (avgSessionLaps? and raceLaps? and avgSessionLaps < raceLaps) or avgSessionLaps? and not raceLaps?
                        calcLaps = avgSessionLaps.toFixed if .1 < avgSessionLaps % 1 < .9 then 1 else 2
                        sessionLaps = "&asymp;#{calcLaps}"
                    else if raceLaps?
                        sessionLaps = raceLaps
                else if avgLapTimes[carClass]
                    avgSessionLaps = avgLapTimes[carClass].sessionLaps
                    if session.ResultsOfficial
                        sessionLaps = lapsComplete
                    else if avgSessionLaps > 0 and \
                            (not (newSessionLaps > 0) or avgSessionLaps < newSessionLaps - 1)
                        calcLaps = avgSessionLaps.toFixed if .1 < avgSessionLaps % 1 < .9 then 1 else 2
                        sessionLaps = "&asymp;#{calcLaps}"
            else if not (newSessionLaps > 0)
                sessionLaps = null
            updateSessionLap()
        scope.$watch 'ir.SessionNum', updateSessionLaps
        scope.$watch 'ir.SessionInfo', updateSessionLaps

        updateAvgLapTimes = ->
            session = ir.SessionInfo.Sessions[ir.SessionNum]
            if session.SessionType != 'Race'
                return
            results = session.ResultsPositions
            if not results?
                return
            for pos in results
                if pos.ClassPosition != 0 or pos.CarIdx not of ir.DriversByCarIdx
                    continue
                carClass = ir.DriversByCarIdx[pos.CarIdx].CarClassID.toString()
                data = avgLapTimes[carClass] ?=
                    lapsComplete: 0
                    lapTimes: []
                    avgLapTime: null
                    sessionLaps: null
                    sessionTimeRemain: null
                if pos.LapsComplete < 2 or pos.LapsComplete <= data.lapsComplete
                    continue
                data.lapsComplete = pos.LapsComplete
                if ir.SessionState != 4
                    continue
                if pos.LastTime > 0 and not (ir.SessionFlags & (0x8000 | 0x4000))
                    data.lapTimes.push pos.LastTime
                if ir.SessionTimeRemain? and 0 < ir.SessionTimeRemain < 604800
                    while data.lapTimes.length > maxLapTimes then data.lapTimes.shift()
                    total = 0
                    # dont count lap times that, minimum + 2secs
                    minLapTime = 2 + Math.min.apply null, data.lapTimes
                    totalTimeCounts = 0
                    for t in data.lapTimes
                        if t < minLapTime
                            total += t
                            totalTimeCounts++
                    data.avgLapTime = total / totalTimeCounts
                    # ir.SessionTimeRemain + 5, update yaml take 5 seconds
                    data.sessionTimeRemain = ir.SessionTimeRemain
                    data.sessionLaps = data.lapsComplete + (ir.SessionTimeRemain + 5) / data.avgLapTime
                    # recalculate for multiclass
                    if ir.CarClassIDs.length > 1
                        fastClass = null
                        for carClass2 of avgLapTimes
                            if not fastClass?
                                fastClass = carClass2
                            else if avgLapTimes[carClass2].avgLapTime < avgLapTimes[fastClass].avgLapTime
                                fastClass = carClass2
                        if fastClass? and fastClass != carClass
                            fastData = avgLapTimes[fastClass]
                            # fastSessionTimeRemain = Math.ceil(fastData.sessionLaps - fastData.lapsComplete) * fastData.avgLapTime
                            # fastSessionTimeRemain = Math.ceil(ir.SessionTimeRemain / fastData.avgLapTime) * fastData.avgLapTime
                            # data.sessionLaps = data.lapsComplete + fastSessionTimeRemain / data.avgLapTime

                            # data.sessionLaps = Math.ceil(fastData.sessionLaps) * fastData.avgLapTime / data.avgLapTime

                            fastSessionTimeRemain = Math.ceil(fastData.sessionLaps - fastData.lapsComplete) * fastData.avgLapTime
                            fastSessionTimeRemain -= fastData.sessionTimeRemain - data.sessionTimeRemain
                            fastSessionTimeRemain = Math.max 1, fastSessionTimeRemain
                            data.sessionLaps = data.lapsComplete + fastSessionTimeRemain / data.avgLapTime

        scope.$watch 'ir.connected', (n, o) ->
            carIdx = null
            sessionLaps = null
            carIdxLapWatcher?()
            avgLapTimes = {}

app.directive 'appSessionTime', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        sessionTotalTime = null
        lastResultsLapsComplete = null
        lastLapTime = null
        forceUseSessionTime = false

        updateSessionTime = ->
            if not forceUseSessionTime and 0 < ir.SessionTimeRemain < 604800
                time = ir.SessionTimeRemain
            else if ir.SessionTime > 0
                time = ir.SessionTime
            if not time?
                return
            element.html timeFormat(time, 0, true) + (if sessionTotalTime then "/#{sessionTotalTime}" else '')
        scope.$watch 'ir.SessionTime', updateSessionTime

        updateSessionTotalTime = ->
            if not ir.SessionInfo or not (ir.SessionNum >= 0)
                return
            session = ir.SessionInfo.Sessions[ir.SessionNum]
            time = parseInt(session.SessionTime) or null

            # test
            # time = NaN
            # time = 60*60
            # # session.SessionType = 'Race'
            # session.SessionType = 'Practice'
            # session.SessionLaps = 30
            # time = 1500
            # session.ResultsLapsComplete = 2
            # session.ResultsAverageLapTime = 60

            if session.SessionType != 'Race'
                sessionTotalTime = if time > 0 then sessionTimeFormat(time) else null
            else
                raceLaps = parseInt(session.SessionLaps) or null
                if raceLaps > 0
                    lapTime = null
                    if session.ResultsLapsComplete < 2
                        results = ir.QualifyResultsInfo?.Results or session.QualifyPositions
                        if not results?
                            for s in ir.SessionInfo.Sessions
                                if s.SessionType.search(/qual/i) != -1
                                    if s.ResultsPositions
                                        results = s.ResultsPositions
                                        break
                                else if s.SessionType.search(/race/i) == -1 # not race
                                    results = s.ResultsPositions
                        if results?
                            camCarClassId = ir.DriversByCarIdx[ir.CamCarIdx].CarClassID
                            for p in results
                                if p.ClassPosition == 0 and p.FastestTime > 0 and ir.DriversByCarIdx[p.CarIdx].CarClassID == camCarClassId
                                    lapTime = p.FastestTime
                                    break
                    else if session.ResultsAverageLapTime > 0 and ir.SessionState == 4
                        lapTime = session.ResultsAverageLapTime
                    else
                        lapTime = lastLapTime

                    if lapTime > 0 and lastResultsLapsComplete != session.ResultsLapsComplete
                        lastResultsLapsComplete = session.ResultsLapsComplete
                        lapsLeft = session.SessionLaps - Math.max(0, session.ResultsLapsComplete)
                        calcTime = ir.SessionTime + lapsLeft * lapTime
                        # add grid time
                        if session.ResultsLapsComplete == -1
                            calcTime += 60
                        calcTime = Math.ceil((calcTime - 15) / 60) * 60 # round race time minus 15secs up
                        if calcTime > 0
                            if time > 0 and calcTime > time
                                sessionTotalTime = sessionTimeFormat time
                            else
                                sessionTotalTime = "&asymp;#{sessionTimeFormat calcTime}"
                                forceUseSessionTime = true
                else
                    sessionTotalTime = if time > 0 then sessionTimeFormat(time) else null

                # if session.SessionType == 'Race'
                #         session.SessionLaps > 0 and \
                #         session.ResultsLapsComplete > 1 and \
                #         session.ResultsAverageLapTime > 0
                #     if ir.SessionState == 4 and lastResultsLapsComplete != session.ResultsLapsComplete
                #         lastResultsLapsComplete = session.ResultsLapsComplete
                #         calcTime = ir.SessionTime + (session.SessionLaps - session.ResultsLapsComplete) * session.ResultsAverageLapTime
                #         calcTime = Math.ceil((calcTime - 15) / 60) * 60 # round race time minus 15secs up
                #         if calcTime > time
                #             sessionTotalTime = sessionTimeFormat time
                #         else
                #             sessionTotalTime = "&asymp;#{sessionTimeFormat calcTime}"
                #             forceUseSessionTime = true
                # else if time > 0
                #     sessionTotalTime = sessionTimeFormat time
                # else
                #     sessionTotalTime = null

            # if not isNaN(time)
            #     sessionTotalTime = if time > 0 then sessionTimeFormat time else null
            # else if session.SessionType == 'Race' and \
            #             session.SessionLaps > 0 and \
            #             session.ResultsLapsComplete > 1 and \
            #             session.ResultsAverageLapTime > 0
            #     if ir.SessionState == 4 and \
            #             lastResultsLapsComplete != session.ResultsLapsComplete
            #         calcTime = ir.SessionTime + (session.SessionLaps - session.ResultsLapsComplete) * session.ResultsAverageLapTime
            #         calcTime = Math.ceil(calcTime / 60 - .25) * 60 # round race time minus 15secs up
            #         lastResultsLapsComplete = session.ResultsLapsComplete
            #         sessionTotalTime = "&asymp;#{sessionTimeFormat calcTime}"
            # else
            #     sessionTotalTime = null
            updateSessionTime()
        scope.$watch 'ir.SessionInfo', updateSessionTotalTime
        scope.$watch 'ir.SessionNum', updateSessionTotalTime

        scope.$watch 'ir.connected', (n, o) ->
            sessionTotalTime = null
            lastResultsLapsComplete = null
            lastLapTime = null
            forceUseSessionTime = false

#     .______       _______  __          ___   .___________. __  ____    ____  _______     _______.
#     |   _  \     |   ____||  |        /   \  |           ||  | \   \  /   / |   ____|   /       |
#     |  |_)  |    |  |__   |  |       /  ^  \ `---|  |----`|  |  \   \/   /  |  |__     |   (----`
#     |      /     |   __|  |  |      /  /_\  \    |  |     |  |   \      /   |   __|     \   \
#     |  |\  \----.|  |____ |  `----./  _____  \   |  |     |  |    \    /    |  |____.----)   |
#     | _| `._____||_______||_______/__/     \__\  |__|     |__|     \__/     |_______|_______/
#

app.controller 'RelativesCtrl', ($scope, $element, config, iRData) ->
    ir = $scope.ir = iRData
    carIdx = null
    maxRows = 7
    halfRows = maxRows / 2 | 0

    # hide if disconnected, no car idx, not in the world, not live
    trkLocWatcher = null
    replayFrameWatcher = null
    checkHideCarIdx = null
    $element.addClass 'ng-hide'
    checkRelativesHide = (n, o) ->
        if n == undefined or not ir.CarIdxTrackSurface?
            return
        if ir.CamCarIdx != checkHideCarIdx
            checkHideCarIdx = ir.CamCarIdx
            trkLocWatcher?()
            trkLocWatcher = $scope.$watch "ir.CarIdxTrackSurface[#{checkHideCarIdx}]", checkRelativesHide
        if ir.IsReplayPlaying
            if not replayFrameWatcher?
                replayFrameWatcher = $scope.$watch 'ir.ReplayFrameNumEnd', checkRelativesHide
        else
            replayFrameWatcher?()
            replayFrameWatcher = null
        $element.toggleClass 'ng-hide', \
            not ir.connected or \
            not (checkHideCarIdx >= 0) or \
            ir.CarIdxTrackSurface[checkHideCarIdx] == -1 or \
            (ir.IsReplayPlaying and ir.ReplayFrameNumEnd > 10)

    $scope.$watch 'ir.connected', checkRelativesHide
    $scope.$watch 'ir.CamCarIdx', checkRelativesHide
    $scope.$watch 'ir.IsReplayPlaying', checkRelativesHide

    if config.relativesCompact
        $element.addClass 'compact'
        return

    precise = null
    # updateEvery = 100
    # lastUpdate = -1
    intervals = null
    curPctIndexes = [-1 for i in [0...64]]
    # lastPctIndexes = [-1 for i in [0...64]]

    resetIntervals = ->
        if not precise?
            return
        emptyIntervals = [-1 for i in [0...precise]][0]
        intervals = [emptyIntervals.slice() for i in [0...64]][0]

    $scope.$watch 'ir.WeekendInfo', (n, o) ->
        if not n? or not ir.WeekendInfo?
            return
        precise = Number(ir.WeekendInfo.TrackLength.split(' ')[0]) * 1000 / 2 | 0
        if isNaN precise
            precise = 1000
        resetIntervals()

    $scope.$watch 'ir.SessionNum', resetIntervals

    updateRelativesCarIdxLapDistPct = (n, o) ->
        if not n? or not intervals?
            return

        # curTime = Date.now()
        # if lastUpdate != -1 and curTime - lastUpdate < updateEvery
        #     return
        # lastUpdate = curTime

        relatives = updateRelatives()
        if not relatives?
            return
        sessionTime = ir.SessionTime
        for pct, i in n
            if pct == -1
                continue
            curPctIndex = Math.round pct * (precise - 1)
            lastPctIndex = curPctIndexes[i]
            curInterval = intervals[i]
            if curPctIndex != lastPctIndex
                # lastPctIndexes[i] = curPctIndexes[i]
                curPctIndexes[i] = curPctIndex
                curInterval[curPctIndex] = sessionTime
                # fill gap between last and cur indexes with -1
                if curPctIndex > lastPctIndex
                    for j in [lastPctIndex + 1...curPctIndex]
                        curInterval[j] = -1
                else
                    for j in [0...curPctIndex]
                        curInterval[j] = -1
                    for j in [lastPctIndex + 1..precise]
                        curInterval[j] = -1
            # else if ir.CarIdxTrackSurface[i] == 1
            #     curInterval[curPctIndex] = sessionTime

        curPctIndex = curPctIndexes[carIdx]
        # lastPctIndex = lastPctIndexes[carIdx]

        curTime = intervals[carIdx][curPctIndex]
        # lastCurTime = intervals[carIdx][lastPctIndex]

        $scope.intervals = for pCarIdx, i in relatives
            if pCarIdx == carIdx
                0
            else if pCarIdx < 0 or curTime == -1
                null
            else if i < halfRows
                # otherCurTime = intervals[pCarIdx][curPctIndexes[pCarIdx]]
                otherCurTime = curTime
                otherTime = intervals[pCarIdx][curPctIndex]
                # if otherCurTime != -1 and otherTime != -1
                if otherTime != -1
                    # time = otherCurTime - otherTime
                    time = curTime - otherTime
                    if time < 0 or time > 120
                        null
                    else time
                else null
            else
                otherTime = intervals[carIdx][curPctIndexes[pCarIdx]]
                if otherTime != -1
                    time = otherTime - curTime
                    if time == 0
                        -.0001
                    else if time > 0 or time < -120
                        null
                    else time
                else null

            # else if i < halfRows
            #     otherTime = intervals[pCarIdx][curPctIndex]
            #     if otherTime != -1
            #         time = curTime - otherTime
            #         if lastCurTime != -1
            #             lastOtherTime = intervals[pCarIdx][lastPctIndex]
            #             if lastOtherTime? and lastOtherTime != -1
            #                 lastTime = lastCurTime - lastOtherTime
            #                 if (time > 0) == (lastTime > 0)
            #                     time = (time + lastTime) / 2
            #                 else time
            #             else time
            #         else time
            #     else null
            # else
            #     prevPctIndex = curPctIndexes[pCarIdx]
            #     otherTime = intervals[carIdx][prevPctIndex]
            #     if otherTime != -1
            #         time = otherTime - curTime
            #         if time == 0
            #             time = -.0001
            #         if lastCurTime != -1
            #             prevLastCarPctIndex = lastPctIndexes[pCarIdx]
            #             lastOtherTime = intervals[carIdx][prevLastCarPctIndex]
            #             if lastOtherTime? and lastOtherTime != -1
            #                 lastTime = lastOtherTime - lastCurTime
            #                 if (time > 0) == (lastTime > 0)
            #                     time = (time + lastTime) / 2
            #                     if time == 0 or time > 0
            #                         time = -.0001
            #                     else time
            #                 else time
            #             else time
            #         else time
            #     else null
    $scope.$watch 'ir.CarIdxLapDistPct', updateRelativesCarIdxLapDistPct

    $scope.$watch 'ir.CamCarIdx', (n, o) ->
        carIdx = n
        updateRelatives()

    updateRelatives = ->
        if not carIdx? or carIdx == -1 or \
                not ir.SessionInfo or not (ir.SessionNum >= 0) or \
                not ir.DriversByCarIdx
            return $scope.relatives = null

        session = ir.SessionInfo.Sessions[ir.SessionNum]
        $scope.relativesType = session.SessionType
        results = session.ResultsPositions or []
        if not results.length and (ir.QualifyResultsInfo or session.QualifyPositions)
            $scope.relativesType = 'QualifyResults'
            results = ir.QualifyResultsInfo?.Results or session.QualifyPositions

        relatives = for pct, i in ir.CarIdxLapDistPct
            driverInfo = ir.DriversByCarIdx[i]
            if pct != -1 and driverInfo and driverInfo.UserID != -1 then i else continue

        curCarLapDist = ir.CarIdxLapDistPct[carIdx]
        if curCarLapDist == -1
            return $scope.relatives = null

        calcDiff = (carIdx) ->
            diff = ir.CarIdxLapDistPct[carIdx] - curCarLapDist
            if diff < -.5 then diff + 1 else if diff > .5 then diff - 1 else diff

        relatives.sort (a, b) ->
            aDiff = calcDiff a
            bDiff = calcDiff b
            bDiff - aDiff

        # find index in relatives of current cam car idx
        curCarIndex = relatives.indexOf carIdx

        if curCarIndex < halfRows
            relatives = relatives[..curCarIndex + halfRows]
            for i in [0...halfRows - curCarIndex]
                relatives.unshift relatives.length - maxRows
        else
            relatives = relatives[curCarIndex - halfRows .. curCarIndex + halfRows]

        $scope.relatives = relatives

app.directive 'appRelativesRow', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appRelativesRow, (n, o) ->
            carIdx = n
            element.toggleClass 'divider', not (carIdx >= 0)

        scope.$watch 'ir.CamCarIdx', (n, o) ->
            element.toggleClass 'current', carIdx == n

        updateRelativesRow = ->
            camCarIdx = ir.CamCarIdx
            relativesType = scope.$parent.relativesType
            if relativesType != 'Race' or camCarIdx < 0 or carIdx == camCarIdx
                element.removeClass 'lapper faraway'
                return
            camCarDist = ir.CarIdxLap[camCarIdx] + ir.CarIdxLapDistPct[camCarIdx]
            carDist = ir.CarIdxLap[carIdx] + ir.CarIdxLapDistPct[carIdx]
            element.toggleClass 'lapper', camCarDist - carDist > .5
            element.toggleClass 'faraway', camCarDist - carDist < -.5
        scope.$watch 'ir.CarIdxLapDistPct', updateRelativesRow

        scope.$watch 'ir.CarIdxOnPitRoad', (n, o) ->
            element.toggleClass 'pit', if carIdx >= 0 then n[carIdx] else false

app.directive 'appRelativesPosition', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appRelativesPosition, (n, o) ->
            carIdx = n
            updateRelativesPosition()

        updateRelativesPosition = ->
            if not carIdx? or carIdx < 0 or not ir.SessionInfo or not (ir.SessionNum >= 0)
                element.text ''
                return
            relativesType = scope.$parent.relativesType
            isQualifyResults = relativesType == 'QualifyResults'
            if isQualifyResults
                position = ir.QualifyResultsByCarIdx[carIdx]
            # results = ir.SessionInfo.Sessions[ir.SessionNum].ResultsPositions
            if carIdx of ir.PositionsByCarIdx[ir.SessionNum]
                position = ir.PositionsByCarIdx[ir.SessionNum][carIdx]
            if position
                element.text position.Position + (if isQualifyResults then 1 else 0)
            else
                element.text ''

        scope.$watch 'ir.SessionInfo', updateRelativesPosition
        scope.$watch 'ir.SessionNum', updateRelativesPosition


app.directive 'appRelativesClassPosition', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appRelativesClassPosition, (n, o) ->
            carIdx = n
            updateRelativesClassPosition()
            updateRelativesClassPositionColor()

        updateRelativesClassPosition = ->
            if not ir.CarClassIDs or ir.CarClassIDs.length < 2 or not (ir.SessionNum >= 0)
                element.addClass 'ng-hide'
                return
            element.removeClass 'ng-hide'
            relativesType = scope.$parent.relativesType
            isQualifyResults = relativesType == 'QualifyResults'
            if isQualifyResults
                position = ir.QualifyResultsByCarIdx[carIdx]
            else
                positions = ir.PositionsByCarIdx[ir.SessionNum]
                if carIdx not of positions
                    element.text '-'
                    return
                position = positions[carIdx]
            if position?
                element.text position.ClassPosition + 1

        scope.$watch 'ir.DriverInfo', updateRelativesClassPosition
        scope.$watch 'ir.SessionInfo', updateRelativesClassPosition
        scope.$watch 'ir.SessionNum', updateRelativesClassPosition

        updateRelativesClassPositionColor = ->
            if not (carIdx >= 0) or not ir.DriversByCarIdx? or \
                    carIdx not of ir.DriversByCarIdx
                return
            driver = ir.DriversByCarIdx[carIdx]
            carClassColor = driver.CarClassColor
            if carClassColor == 0xffffff
                carClassColor = 0xffda59
            if carClassColor == 0
                carClassId = driver.CarClassID
                for d in ir.DriverInfo.Drivers
                    if d.CarClassID == carClassId and d.CarClassColor
                        carClassColor = d.CarClassColor
            element.css
                background: "rgba(#{carClassColor >> 16},\
                    #{carClassColor >> 8 & 0xff},\
                    #{carClassColor & 0xff},\
                    1)"

        scope.$watch 'ir.DriverInfo', updateRelativesClassPositionColor

app.directive 'appSafetyRating', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null
        licenseLetter = ['R', 'D', 'C', 'B', 'A', 'P', 'W']
        licenseColors = [
            0xfc0706 # R
            0xfc8a27 # D
            0xfeec04 # C
            0x00c702 # B
            0x0153db # A
            0x000000 # P
            0x000000 # W
        ]

        scope.$watch attrs.appSafetyRating, (n, o) ->
            carIdx = n
            element.toggleClass 'ng-hide', not (carIdx >= 0)
            if carIdx >= 0
                updateSafetyRating()

        updateSafetyRating = ->
            if not (carIdx >= 0)
                return
            driver = ir.DriversByCarIdx[carIdx]

            # licenseClassIndex = Math.max(0, driver.LicLevel - 1) / 4 | 0
            # licenseClass = ['R', 'D', 'C', 'B', 'A', 'P', 'W'][licenseClassIndex]
            # sr = ((driver.LicSubLevel / 10 | 0) / 10).toFixed 1
            # element.text licenseClass + sr

            licenseClassIndex = licenseLetter.indexOf(driver.LicString[0])
            element.text driver.LicString.replace(/(\w).*? ([\d.]{3}).*/, '$1$2')

            # licenseColor = driver.LicColor.toString 16
            licenseColor = licenseColors[licenseClassIndex].toString 16
            while licenseColor.length < 6
                licenseColor = '0' + licenseColor
            element.css
                color: if licenseClassIndex > 0 and licenseClassIndex < 4 then 'black' else 'white'
                background: "##{licenseColor}"
                border: if licenseClassIndex > 4 then 'grey 1px solid' else 'none'

        scope.$watch 'ir.DriverInfo', updateSafetyRating

app.directive 'appIrating', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null

        scope.$watch attrs.appIrating, (n, o) ->
            carIdx = n
            element.toggleClass 'ng-hide', not (carIdx >= 0)
            if carIdx >= 0
                updateIRating()

        updateIRating = ->
            if carIdx >= 0
                d = ir.DriversByCarIdx[carIdx]
                element.text "#{((d.IRating / 100 | 0) / 10).toFixed 1}#{if d.IRating >= 10000 then '' else 'k'}"

        scope.$watch 'ir.DriverInfo', updateIRating

app.directive 'appRelativesInt', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        carIdx = null
        lastUpdate = null

        scope.$watch attrs.appRelativesInt, (n, o) ->
            carIdx = n
            element.text ''
            updateRelativesInt()

        scope.$watch 'ir.CamCarIdx', (n, o) ->
            lastUpdate = null
            element.text ''

        scope.$watch '$parent.intervals', updateRelativesInt = ->
            intervals = scope.$parent.intervals
            if not (carIdx >= 0) or not intervals
                element.text ''
                return
            if carIdx == ir.CamCarIdx
                element.text '0.0'
                return
            time = intervals[scope.$index]
            now = Date.now()
            if time?
                lastUpdate = now
                element.text timeFormat time, 1
            else if lastUpdate? and now - lastUpdate >= 5000
                lastUpdate = null
                element.text ''

        # scope.$watch 'ir.CarIdxEstTime', updateRelativesInt = ->
        #     relatives = scope.$parent.relatives
        #     if not relatives
        #         element.text ''
        #         return
        #     # if carIdx == ir.CamCarIdx
        #     #     element.text '0.0'
        #     #     return
        #     time = ir.CarIdxEstTime[relatives[scope.$index]] - ir.CarIdxEstTime[ir.CamCarIdx]
        #     while time < -.5 * ir.DriverInfo.DriverCarEstLapTime
        #         time += ir.DriverInfo.DriverCarEstLapTime
        #     while time > .5 * ir.DriverInfo.DriverCarEstLapTime
        #         time -= ir.DriverInfo.DriverCarEstLapTime
        #     if scope.$index < relatives.length / 2
        #         while time < 0
        #             time += ir.DriverInfo.DriverCarEstLapTime
        #     if scope.$index > relatives.length / 2
        #         while time > 0
        #             time -= ir.DriverInfo.DriverCarEstLapTime
        #     # now = Date.now()
        #     if time?
        #         # lastUpdate = now
        #         element.text timeFormat time, 1
        #     else if lastUpdate? and now - lastUpdate >= 5000
        #         # lastUpdate = null
        #         element.text ''

#       ______     ___      .______
#      /      |   /   \     |   _  \
#     |  ,----'  /  ^  \    |  |_)  |
#     |  |      /  /_\  \   |      /
#     |  `----./  _____  \  |  |\  \----.
#      \______/__/     \__\ | _| `._____|
#

app.controller 'CarCtrl', ($scope, $element, config, iRData) ->
    $scope.ir = ir = iRData

    $scope.showFuel = config.carFuel
    $scope.showTemps = config.carTemps
    $scope.showWind = config.carWind
    $scope.showWeatherSOF = config.carWeatherSOF

    if (not $scope.showFuel) and (not $scope.showTemps) and (not $scope.showWind) and (not $scope.showWeatherSOF)
        $element.remove()
        return

    checkCarHide = ->
        $element.toggleClass 'ng-hide', not ir.connected or not ir.IsOnTrack
    $scope.$watch 'ir.connected', checkCarHide
    $scope.$watch 'ir.IsOnTrack', checkCarHide

    useKg = false
    useImpGal = false
    $scope.normalizeFuelLevel = (fuel) ->
        if useKg
            fuel *= ir.DriverInfo.DriverCarFuelKgPerLtr or .75
        if not ir.DisplayUnits
            if useImpGal
                fuel *= 0.21996924829909
            # kg to lbs
            else if useKg
                fuel *= 2.20462262
            else
                fuel *= 0.264172052
        return fuel

    $scope.$watch 'ir.DriverInfo', (n, o) ->
        if not n?
            return
        d = ir.DriversByCarIdx[ir.DriverInfo.DriverCarIdx]
        useKg = d.CarID in [33, 39, 71, 77]
        useImpGal = d.CarID in [25, 42]

app.directive 'appCarFuel', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        scope.$watch 'ir.FuelLevel', (n, o) ->
            if not n? or n < 0
                return
            fuel = scope.normalizeFuelLevel n
            element.text fuel.toFixed 2

app.directive 'appCarFuelCalc', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        max = 7
        fuels = []
        lastDist = null
        lastFuelLevel = null
        lapStarted = false
        # lapWatcher = null
        fuelWacther = null
        watchPlayerTrackSurface = null

        updateCarFuelCalc = (updateDisplayOnly = false) ->
            dist = if ir.LapDistPct != -1 then ir.LapDistPct else null
            curFuelLevel = ir.FuelLevel
            lapChanged = false

            if ir.IsOnTrack

                if lastFuelLevel? and curFuelLevel > lastFuelLevel
                    lapStarted = false

                if dist? and dist != -1
                    if dist < .1 and lastDist? and lastDist > .9 and checkFlags()
                        lapChanged = lapStarted
                        if not lapStarted
                            updateDisplayOnly = true
                            lastFuelLevel = curFuelLevel
                        lapStarted = true
                    lastDist = dist

            # test
            # fuels = [1.1,2.2,3.3]

            if lapChanged and ir.SessionState == 4
                legitLap = not (ir.OnPitRoad or ir.SessionFlags & (0x4000 | 0x8000))
                if legitLap and lastFuelLevel? and lastFuelLevel > curFuelLevel
                    fuels.push lastFuelLevel - curFuelLevel
                    while fuels.length > max then fuels.shift()
                lastFuelLevel = curFuelLevel

            if lapChanged or updateDisplayOnly
                if fuels.length
                    f = fuels.slice()
                    if f.length >= 3
                        f = f.sort()[1...-1]
                    total = f.reduce (a, b) -> a + b
                    perLap = total / f.length
                    remainLaps = curFuelLevel / perLap

                    element.html "#{scope.normalizeFuelLevel(perLap).toFixed 2}&asymp;#{remainLaps.toFixed 1}"
                else
                    element.text ''

        scope.$watch 'ir.LapDistPct', -> updateCarFuelCalc()

        scope.$watch 'ir.LFwearR', (n, o) ->
            lapStarted = false

        scope.$watch 'ir.DriverInfo', (n, o) ->
            if not n?
                return
            if not watchPlayerTrackSurface?
                watchPlayerTrackSurface = scope.$watch 'ir.PlayerTrackSurface', (n, o) ->
                    if n == -1 or (o == 3 and n == 1) or (o == 1 and n == 3)
                        lastDist = null
                        lastFuelLevel = null
                        lapStarted = false
                        # lapWatcher?()
                        # lapWatcher = null
                    # if n != -1 and n != 1# and not lapWatcher?
                    #     updateCarFuelCalc true
                    #     # lapWatcher?()
                    #     # lapWatcher = scope.$watch "ir.LapDistPct", -> updateCarFuelCalc()

        scope.$watch 'ir.IsOnTrack', (n, o) ->
            if not n
                lastDist = null
                lastFuelLevel = null
                lapStarted = false
                # lapWatcher?()
                # lapWatcher = null
            else
                # lapWatcher?()
                # lapWatcher = scope.$watch "ir.LapDistPct", -> updateCarFuelCalc()
                updateCarFuelCalc true

        scope.$watch 'ir.OnPitRoad', (n, o) ->
            # lastFuelLevel = null
            if n
                lapStarted = false
                fuelWacther = scope.$watch 'ir.FuelLevel', (n, o) ->
                    if n > o or not o?
                        updateCarFuelCalc true
            else if fuelWacther?
                fuelWacther()
                fuelWacther = null

        scope.$watch 'ir.SessionFlags', checkFlags = ->
            flags = ir.SessionFlags
            if not flags? or flags == -1
                false
            else if flags & (0x200 | 0x0400 | 0x4000 | 0x8000 | 0x080000)
                # console.log 'flag', flags.toString 16
                lapStarted = false
                false
            true

        scope.$watch 'ir.connected', (n, o) ->
            fuels = []
            lastDist = null
            lastFuelLevel = null
            lapStarted = false
            watchPlayerTrackSurface?()
            watchPlayerTrackSurface = null
            # lapWatcher?()
            # lapWatcher = null
            element.text ''

app.directive 'appCarTemp', (config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        scope.$watchGroup [attrs.appCarTemp, 'ir.DisplayUnits'], (n, o) ->
            n = n[0]
            if not n? or n < 0
                return
            temp = n
            if not ir.DisplayUnits
                temp = temp * 9/5 + 32
            element.html "#{temp.toFixed 1}&deg;#{if ir.DisplayUnits then 'C' else 'F'}"

app.directive 'appCarWindDir', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        lastValues = null
        points = [0, 10, 20, 40, 50]
        colors = [
            [170, 170, 170]
            [204, 204, 204]
            [34, 170, 255]
            [255, 204, 0]
            [255, 34, 34]
        ]

        directionUpdate = ->
            wd = (ir.WindDir - ir.YawNorth) * 180/Math.PI
            ws = ir.WindVel * 3.6
            if isNaN(wd) or isNaN(ws)
                return
            newValues = [wd, ws]
            if lastValues? and angular.equals lastValues, newValues
                return
            lastValues = newValues
            element.css
                stroke: getColor ws, points, colors
                transform: "rotate(#{wd + 180}deg)"

        scope.$watch 'ir.WindDir', directionUpdate
        scope.$watch 'ir.WindVel', directionUpdate
        scope.$watch 'ir.YawNorth', directionUpdate

app.directive 'appCarWindSpeed', (config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        scope.$watchGroup [attrs.appCarWindSpeed, 'ir.DisplayUnits'], (n, o) ->
            n = n[0]
            if not n? or n < 0
                return
            speed = n * 3.6
            if not ir.DisplayUnits
                speed *= 0.621371192
            element.html speed.toFixed 0

app.directive 'appCarTrackTemp', (config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        scope.$watchGroup ['ir.TrackTempCrew', 'ir.DisplayUnits'], ->
            trackTemp = ir.TrackTempCrew
            tempUnits = 'C'
            if not ir.DisplayUnits
                trackTemp = trackTemp * 9/5 + 32
                tempUnits = 'F'
            element.html "#{trackTemp.toFixed 0}&deg;#{tempUnits}"

app.directive 'appCarSof', (config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        scope.$watch 'ir.DriverInfo', ->
            if not ir.DriverInfo? then return
            myClassId = ir.DriversByCarIdx[ir.DriverInfo.DriverCarIdx].CarClassID
            sof = 0
            magicNumber = 1600
            numberDrivers = 0
            for d in ir.DriverInfo.Drivers
                if d.UserID == -1 or d.IsSpectator or d.CarClassID != myClassId then continue
                numberDrivers++
                sof += Math.pow(2, -d.IRating / magicNumber)
            if sof and numberDrivers
                sof = magicNumber / Math.log(2) * Math.log(numberDrivers / sof)
                element.text "#{(sof / 1000).toFixed 1}k"

#     .___________.____    ____ .______       _______     _______.
#     |           |\   \  /   / |   _  \     |   ____|   /       |
#     `---|  |----` \   \/   /  |  |_)  |    |  |__     |   (----`
#         |  |       \_    _/   |      /     |   __|     \   \
#         |  |         |  |     |  |\  \----.|  |____.----)   |
#         |__|         |__|     | _| `._____||_______|_______/
#

app.controller 'TyresCtrl', ($scope, $element, $interval, config, iRData) ->
    if not config.showTyres
        $element.remove()
        return

    ir = $scope.ir = iRData

    ibtWaiter = null
    ibtWaiterCounter = 0
    $scope.$watch 'ir.IsOnTrack', (n, o) ->
        if not n
            $element.addClass 'ng-hide'
        else
            if ibtWaiter?
                ibtWaiter()
            ibtWaiterCounter = 0
            ibtWaiter = $scope.$watch 'ir.RRtempL', (n, o) ->
                if n?
                    ibtWaiterCounter++
                # if ibtWaiterCounter >= 2
                if ibtWaiterCounter >= 1
                    ibtWaiter()
                    ibtWaiter = null
                    $element.removeClass 'ng-hide'

    $scope.avgDelay = 1000
    $scope.avgDelayThreshold = 1

    # lastTimeGetValue = []
    # $scope.avgDelay = 1000
    # $scope.avgDelayThreshold = 1.5 * 1000 / config.fps
    # $scope.$watch 'ir.LFtempR', (n, o) ->
    #     if not n?
    #         return
    #     lastTimeGetValue.push Date.now()
    #     while lastTimeGetValue.length > 5
    #         lastTimeGetValue.shift()
    #     if lastTimeGetValue.length > 1
    #         $scope.avgDelay = (lastTimeGetValue[lastTimeGetValue.length - 1] - lastTimeGetValue[0]) / (lastTimeGetValue.length - 1)

    # test
    # $interval ->
    #     ir.LFtempR = ir.RFtempL = 40 + 80 * Math.random()
    #     ir.LFtempM = ir.RFtempM = ir.LFtempR - 10 * Math.random()
    #     ir.LFtempL = ir.RFtempR = ir.LFtempM - 10 * Math.random()

    #     ir.LRtempR = ir.RRtempL = 40 + 80 * Math.random()
    #     ir.LRtempM = ir.RRtempM = ir.LRtempR - 10 * Math.random()
    #     ir.LRtempL = ir.RRtempR = ir.LRtempM - 10 * Math.random()

    #     ir.LFpressure = ir.RFpressure = 190 + 10 * Math.random()
    #     ir.LRpressure = ir.RRpressure = 190 + 10 * Math.random()
    # , 1000

app.directive 'appTyresTemp', ($interval, config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        temp = null
        lastTemp = null
        fps = config.fps
        frame = 0
        promise = null

        scope.$watch attrs.appTyresTemp, updateTyresTemp = (n, o) ->
            if not n? then return
            lastTemp = temp
            temp = if n.length? then n[n.length - 1] else n
            if not ir.DisplayUnits
                temp = temp * 9/5 + 32

            $interval.cancel promise
            if scope.avgDelay > scope.avgDelayThreshold and lastTemp?
                frame = 0
                frames = Math.max 1, Math.round scope.avgDelay / (1000 / fps)
                promise = $interval ->
                    value = lastTemp + ++frame * (temp - lastTemp) / frames
                    if not isNaN(value) or value > 0 or value < 1000
                        element.text value.toFixed()
                , 1000 / fps, frames, false
                element.text lastTemp.toFixed()
            else
                element.text temp.toFixed()

        scope.$watch 'ir.IsOnTrack', (n, o) ->
            if not n
                $interval.cancel promise
                temp = null
                lastTemp = null

app.directive 'appTyresTempBar', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        temps = [40, 100, 125, 200]
        colors = [
            [34, 34, 255]
            [34, 255, 34]
            [255, 34, 34]
            [127, 0, 0]
        ]

        scope.$watch attrs.appTyresTempBar, (n, o) ->
            if not n? then return
            temp = if n.length? then n[n.length - 1] else n
            element.css
                background: getColor temp, temps, colors
                '-webkit-transition-duration': "#{scope.avgDelay / 1000}s"

app.directive 'appTyresPres', ($interval, config, iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        pressure = null
        lastPressure = null
        fps = config.fps
        frame = 0
        promise = null
        precise = null
        unit = null

        scope.$watch 'ir.DisplayUnits', ->
            precise = if ir.DisplayUnits then 2 else 3
            unit = if ir.DisplayUnits then 'kPa' else 'psi'
            updateTyresPres scope.$eval attrs.appTyresPres

        scope.$watch attrs.appTyresPres, updateTyresPres = (n, o) ->
            if not n? then return
            lastPressure = pressure
            pressure = if n.length? then n[n.length - 1] else n
            if not ir.DisplayUnits
                pressure *= 0.145037738

            $interval.cancel promise
            if scope.avgDelay > scope.avgDelayThreshold and lastPressure?
                frame = 0
                frames = Math.max 1, Math.round scope.avgDelay / (1000 / fps)
                promise = $interval ->
                    value = lastPressure + ++frame * (pressure - lastPressure) / frames
                    if not isNaN(value) or value > 0 or value < 1000
                        element.text "#{value.toFixed precise} #{unit}"
                , 1000 / fps, frames, false
                element.text "#{lastPressure.toFixed precise} #{unit}"
            else
                element.text "#{pressure.toFixed precise} #{unit}"

        scope.$watch 'ir.IsOnTrack', (n, o) ->
            if not n
                $interval.cancel promise
                pressure = null
                lastPressure = null

#     .___________.____    __    ____  __  .___________.  ______  __    __
#     |           |\   \  /  \  /   / |  | |           | /      ||  |  |  |
#     `---|  |----` \   \/    \/   /  |  | `---|  |----`|  ,----'|  |__|  |
#         |  |       \            /   |  |     |  |     |  |     |   __   |
#         |  |        \    /\    /    |  |     |  |     |  `----.|  |  |  |
#         |__|         \__/  \__/     |__|     |__|      \______||__|  |__|
#

app.controller 'TwitchCtrl', ($scope, $element, $interval, $timeout, $sce, $http, config) ->
    $element.addClass 'ng-hide'

    channel = config.twitchChannel
    if not channel
        return

    channel = channel.toLowerCase()
    baseUri = 'https://api.twitch.tv/kraken'
    clientID = '4lpom5pnvv6hvsqs034mia4zv0gwcs'

    $scope.viewers = 0
    $scope.followers = 0

    followers = []
    newFollowers = []

    updateTwitchViewers = ->
        $http.jsonp $sce.trustAsResourceUrl("#{baseUri}/streams/#{channel}"),
            params:
                client_id: clientID
        .then (response) ->
            if response.data.error?
                return
            stream = response.data.stream
            if not stream?
                return
            if stream.viewers > 0
                $scope.viewers = stream.viewers
                $element.removeClass 'ng-hide'

    getFollowers = (limit, offset, success, error) ->
        $http.jsonp $sce.trustAsResourceUrl("#{baseUri}/channels/#{channel}/follows"),
            params:
                client_id: clientID
                direction: 'DESC'
                limit: limit
                offset: offset
        .then (response) ->
            if response.data.error?
                error response
            else
                success response
        , error

    collectFollowersPagesLeft = null
    grabFollowers = (page=0, limit=100) ->
        getFollowers limit, page * limit,
            (response) ->
                if page == 0
                    $scope.followers = response.data._total
                    if response.data._total == 0 and response.data.follows.length != 0
                        $timeout ->
                            grabFollowers()
                        , 1000
                        return
                    $element.removeClass 'ng-hide'
                    collectFollowersPagesLeft = Math.ceil response.data._total / limit
                for f in response.data.follows
                    if f.user.name not in followers
                        followers.push f.user.name
                collectFollowersPagesLeft--
                if collectFollowersPagesLeft > 0
                    grabFollowers(page + 1, limit)
                else
                    $interval updateTwitchFollowers, 5000
            , (error) ->
                if error?.data?.message == 'Offset too high'
                    $interval updateTwitchFollowers, 5000
                else
                    $timeout ->
                        grabFollowers page, limit
                    , 1000

    showNewFollowerTimeout = null
    showNewFollowerTimeout2 = null
    updateTwitchFollowers = -> getFollowers 5, 0, (response) ->
        # update total followers
        $element.removeClass 'ng-hide'
        if response.data._total > 0 or response.data.follows.length == 0
            $scope.followers = response.data._total

        # dont show notification if no template
        if not config.twitchNewFollowerTmpl
            return

        # fill followers if couldnt grab before
        if not followers.length
            for f in response.data.follows
                if f.user.name not in followers
                    followers.push f.user.name

        # check for new followers
        for f in response.data.follows
            if f.user.name not in followers
                followers.push f.user.name
                newFollowers.push f.user.display_name
            # test
            # newFollowers.push f.user.display_name

        # show next new follower if dont show right now and have new
        if newFollowers.length and not $scope.showNewFollower and not showNewFollowerTimeout2
            showNextNewFollower()

    showNextNewFollower = ->
        if not newFollowers.length
            return
        $scope.newFollower = config.twitchNewFollowerTmpl.split('{0}').join newFollowers.shift()
        $scope.showNewFollower = true
        showNewFollowerTimeout = $timeout ->
            $scope.showNewFollower = false
            if newFollowers.length
                showNewFollowerTimeout2 = $timeout ->
                    showNextNewFollower()
                , 500
            else
                showNewFollowerTimeout2 = null
        , config.twitchNewFollowerTimeout * 1000

    $interval updateTwitchViewers, 5000
    updateTwitchViewers()

    # skip grab followers if no template
    if config.twitchNewFollowerTmpl
        # start grab followers
        grabFollowers()
    else
        $interval updateTwitchFollowers, 5000
        updateTwitchFollowers()

# app.directive 'appTest', ->
#     restrict: 'E'
#     link: (scope, element, attrs) ->
#         ir = scope.ir
#         update = ->
#             v = localStorage['test']
#             if not v
#                 v = 0
#             element.text v
#             localStorage['test'] = ++v
#         setInterval update, 1000

app.filter 'time', -> timeFormat
app.filter 'gap', -> gapFormat

angular.bootstrap document, [app.name]

#      __    __  .___________. __   __          _______.
#     |  |  |  | |           ||  | |  |        /       |
#     |  |  |  | `---|  |----`|  | |  |       |   (----`
#     |  |  |  |     |  |     |  | |  |        \   \
#     |  `--'  |     |  |     |  | |  `----.----)   |
#      \______/      |__|     |__| |_______|_______/
#

timeFormat = (time, precise = 3, showMins = false) ->
    sign = time >= 0
    time = Math.abs time

    if precise > 0
        precisePow = [10, 100, 1000][precise - 1]
        time = Math.round(time * precisePow) / precisePow
    else
        time = Math.round(time)

    h = time / 3600 | 0
    m = (time / 60 | 0) % 60
    s = time % 60
    res = ''

    if h
        res += "#{h}:"
        if m < 10 then m = "0#{m}"
    if m or showMins
        res += "#{m}:"
        if s < 10
            res += "0#{s.toFixed precise}"
        else
            res += s.toFixed precise
    else
        res += s.toFixed precise

    if not sign
        res = "-#{res}"

    res

gapFormat = (time) ->
    if time > 1000
        return (time - 1000 | 0) + 'L'
    if time < 1
        return timeFormat time, 2
    timeFormat time, 1

sessionTimeFormat = (time) ->
    h = time / 3600 | 0
    m = (time / 60 | 0) % 60
    res = ''
    if h
        res += "#{h}h"
    if m
        if h and m < 10
            res += "0#{m}m"
        else
            res += "#{m}m"
    res

getColor = (point, points, colors) ->
    len = points.length
    if point <= points[0]
        color = colors[0]
    else if point >= points[len - 1]
        color = colors[len - 1]
    else
        for t, i in points
            if point < t
                index = i
                break
        color = [0, 0, 0]
        ca = colors[index - 1]
        cb = colors[index]
        p = (point - points[index - 1]) / (points[index] - points[index - 1])
        p = Math.max(0, Math.min(1, p))
        for i in [0...3]
            color[i] = Math.round ca[i] - (ca[i] - cb[i]) * p
    "rgb(#{color.join ','})"
