app = angular.module 'stream-overlay', [
    'ngRoute'
    'mgcrea.ngStrap.navbar'
    'LocalStorageModule'
    'kutu.markdown'
]

app.config ($routeProvider) ->
    $routeProvider
        .when '/',
            templateUrl: 'tmpl/index.html'
        .when '/twitch',
            templateUrl: 'tmpl/twitch.html'
            controller: 'TwitchCtrl'
            title: 'Twitch'
        .when '/settings',
            templateUrl: 'tmpl/settings.html'
            controller: 'SettingsCtrl'
            title: 'Settings'
        .otherwise redirectTo: '/'

app.config (localStorageServiceProvider) ->
    localStorageServiceProvider.setPrefix app.name

app.run ($rootScope, $sce) ->
    $rootScope.$on '$routeChangeSuccess', (event, current, previous) ->
        title = 'Stream Overlay &middot; iRacing Browser Apps'
        if current.$$route.title?
            title = current.$$route.title + ' &middot; ' + title
        $rootScope.title = $sce.trustAsHtml title

app.service 'iRData', ($rootScope, localStorageService) ->
    settings = localStorageService.get('settings') or {}

    ir = new IRacing \
        # request params
        [
            'SessionNum'
            'IsOnTrack'
        ],
        # request params once
        [
            'DriverInfo'
            'SessionInfo'
            'WeekendInfo'
        ],
        1,
        settings.host or '127.0.0.1:8182'

    ir.onConnect = ->
        ir.data.connected = true
        $rootScope.$apply()

    ir.onDisconnect = ->
        ir.data.connected = false
        $rootScope.$apply()

    ir.onUpdate = (keys) ->
        $rootScope.$apply()

    return ir.data

#          _______. _______ .___________.___________. __  .__   __.   _______      _______.
#         /       ||   ____||           |           ||  | |  \ |  |  /  _____|    /       |
#        |   (----`|  |__   `---|  |----`---|  |----`|  | |   \|  | |  |  __     |   (----`
#         \   \    |   __|      |  |        |  |     |  | |  . `  | |  | |_ |     \   \
#     .----)   |   |  |____     |  |        |  |     |  | |  |\   | |  |__| | .----)   |
#     |_______/    |_______|    |__|        |__|     |__| |__| \__|  \______| |_______/
#

app.controller 'SettingsCtrl', ($scope, localStorageService) ->
    defaultSettings =
        host: '127.0.0.1:8182'
        fps: 60
        standingsMaxRows: 20
        standingsWindow: 5
        standingsMulticlass: true
        relativesCompact: false
        carFuel: true
        carTemps: true
        carWind: false
        carWeatherSOF: false
        showTyres: false
        twitchChannel: ''
        twitchNewFollowerTmpl: 'All HAIL new follower: <b>{0}</b>'
        twitchNewFollowerTimeout: 10

    $scope.settings = settings = localStorageService.get('settings') or {}
    settings.host ?= null
    settings.carTemps ?= false
    settings.carWeatherSOF ?= true
    for p of defaultSettings
        if p not of settings
            settings[p] = defaultSettings[p]

    $scope.saveSettings = saveSettings = ->
        # reset host
        if settings.host == ''
            settings.host = null
        settings.fps = Math.min 60, Math.max(1, settings.fps)
        settings.standingsWindow = (settings.standingsWindow / 2 | 0) * 2 + 1
        settings.standingsMaxRows = Math.max settings.standingsMaxRows or 1, settings.standingsWindow + 2
        # if not settings.twitchChannel
        #     delete settings.twitchChannel
        # if not settings.showTyres
        #     delete settings.showTyres
        localStorageService.set 'settings', settings
        updateURL()

    actualKeys = [
        'host'
        'fps'
        'standingsMaxRows'
        'standingsWindow'
        'standingsMulticlass'
        'relativesCompact'
        'carFuel'
        'carTemps'
        'carWind'
        'carWeatherSOF'
        'twitchChannel'
        'twitchNewFollowerTmpl'
        'twitchNewFollowerTimeout'
        'showTyres'
    ]

    updateURL = ->
        params = []
        for k, v of settings
            if k of defaultSettings and v == defaultSettings[k] then continue
            # if v == '' then continue
            if k == 'host' and not v? then continue
            if k == 'twitchNewFollowerTmpl' and not settings.twitchChannel then continue
            if k == 'twitchNewFollowerTimeout' and \
                (settings.twitchChannel == '' or settings.twitchNewFollowerTmpl == '') then continue
            # if k == 'showTyres' and not settings.showTyres then continue
            if k in actualKeys
                params.push "#{k}=#{encodeURIComponent v}"
        $scope.url = "http://#{document.location.host}/stream-overlay/overlay.html\
            #{if params.length then '#?' + params.join '&' else ''}"
    updateURL()

    $scope.changeURL = ->
        params = $scope.url and $scope.url.search(/#\?/) != -1 and $scope.url.split('#?', 2)[1]
        if not params
            return
        for p in params.split '&'
            [k, v] = p.split '=', 2
            if k not of settings
                continue
            nv = Number v
            if not isNaN nv and v.length == nv.toString().length
                v = Number(v)
            settings[k] = v
        saveSettings()

#     .___________.____    __    ____  __  .___________.  ______  __    __
#     |           |\   \  /  \  /   / |  | |           | /      ||  |  |  |
#     `---|  |----` \   \/    \/   /  |  | `---|  |----`|  ,----'|  |__|  |
#         |  |       \            /   |  |     |  |     |  |     |   __   |
#         |  |        \    /\    /    |  |     |  |     |  `----.|  |  |  |
#         |__|         \__/  \__/     |__|     |__|      \______||__|  |__|
#

app.controller 'TwitchCtrl', ($scope, $http, $location, $timeout, $interval, $sce, localStorageService, iRData) ->
    $scope.settings = settings = localStorageService.get('twitch') or {}

    $scope.ir = ir = iRData
    settings.connectedTmpl ?= '{0}: {1} @ {2}'
    settings.disconnectedTmpl ?= 'iRacing'
    settings.autoUpdate ?= true
    settings.showSettingsPanel ?= true
    settings.showStream ?= false
    settings.showChat ?= false
    settings.updateTwitchFollowers ?= true
    settings.showNewFollowers ?= true
    settings.newFollowerSound ?= 'sound/new-follower.ogg'
    settings.newFollowerVolume ?= .5
    settings.noSoundInRaceOrQual ?= true

    # for localhost:8182
    clientId = '4b0ee7g03dih3iowr1et8369lv8cdoz'
    redirectUri = encodeURIComponent 'http://localhost:8182/stream-overlay/#!/twitch'

    # for ir-apps.kutu.ru
    if document.location.host == 'ir-apps.kutu.ru'
        clientId = '4lpom5pnvv6hvsqs034mia4zv0gwcs'
        redirectUri = encodeURIComponent 'http://ir-apps.kutu.ru/stream-overlay/#!/twitch'

    scopes = ['channel_editor']
    token = null
    baseUri = 'https://api.twitch.tv/kraken'

    updateTwitchFollowersInterval = null
    newFollowerSound = null

    hash = $location.hash()
    if hash
        for p in hash.split '&'
            [k, v] = p.split '='
            if k == 'access_token'
                settings[k] = v
                break
        localStorageService.set 'twitch', settings
        $location.hash null

    createNewFollowerSound = (filename) ->
        newFollowerSound = new Audio(filename)
        newFollowerSound.volume = settings.newFollowerVolume
        newFollowerSound.addEventListener 'loadeddata', ->
            $scope.newFollowerSoundError = false
        newFollowerSound.addEventListener 'error', ->
            $scope.newFollowerSoundError = true

    if settings.newFollowerSound
        createNewFollowerSound settings.newFollowerSound

    $scope.saveSettings = saveSettings = ->
        lastSettings = localStorageService.get('twitch') or {}
        localStorageService.set 'twitch', settings
        if lastSettings.showNewFollowers != settings.showNewFollowers
            if settings.showNewFollowers
                updateTwitchFollowersInterval = $interval updateTwitchFollowers, 10000
                updateTwitchFollowers()
            else
                $interval.cancel updateTwitchFollowersInterval
        if lastSettings.newFollowerSound != settings.newFollowerSound
            createNewFollowerSound settings.newFollowerSound
        if newFollowerSound and lastSettings.newFollowerVolume != settings.newFollowerVolume
            newFollowerSound.volume = settings.newFollowerVolume

    toggleSettingsPanelTimeout = null
    $scope.toggleSettingsPanel = ->
        toggleSettingsPanelTimeout = $timeout ->
            settings.showSettingsPanel = !settings.showSettingsPanel
            saveSettings()
        , 500

    $scope.connect = ->
        window.location = "#{baseUri}/oauth2/authorize\
            ?response_type=token\
            &client_id=#{clientId}\
            &redirect_uri=#{redirectUri}\
            &scope=#{scopes.join '+'}"

    checkAuthenticated = ->
        $http.jsonp $sce.trustAsResourceUrl(baseUri),
            params:
                oauth_token: settings.access_token
        .then (response) ->
            console.log response.data
            $scope.ready = true
            $scope.authenticated = response.data.token.valid
            token = response.data.token
            # test
            # token.user_name = 'jamalbutterworth'
            userName = token.user_name
            $scope.userName = userName
            $scope.streamIFrameUrl = $sce.trustAsResourceUrl "http://player.twitch.tv/?channel=#{userName}"
            $scope.chatIFrameUrl = $sce.trustAsResourceUrl "http://www.twitch.tv/#{userName}/chat"

            if not token
                return
            getStatus()

    getStatusTimeout = null
    getStatus = ->
        $timeout.cancel getStatusTimeout
        $scope.statusUpdating = true
        $http.jsonp $sce.trustAsResourceUrl("#{baseUri}/channels/#{token.user_name}"),
            params:
                oauth_token: settings.access_token
        .then (response) ->
            console.log response.data
            if response.data.error
                $scope.error = response.data
                getStatusTimeout = $timeout ->
                    getStatus()
                , 1000
            else
                $scope.error = null
                $scope.status = response.data.status
            $scope.statusUpdating = false

    updateStatusTimeout = null
    $scope.updateStatus = updateStatus = (status) ->
        $timeout.cancel updateStatusTimeout
        if $scope.status == status
            return
        status = encodeURIComponent status
        $scope.statusUpdating = true
        $http.jsonp $sce.trustAsResourceUrl("#{baseUri}/channels/#{token.user_name}"),
            params:
                oauth_token: settings.access_token
                _method: 'put'
                'channel[status]': status
        .then (response) ->
            console.log response.data
            if response.data.error
                $scope.error = response.data
                updateStatusTimeout = $timeout ->
                    updateStatus status
                , 10000
            else
                $scope.error = null
                $scope.status = response.data.status
            $scope.statusUpdating = false

    if settings.access_token
        checkAuthenticated()
    else
        $scope.ready = true

    # test
    # $scope.authenticated = true
    # $scope.ready = true
    # $scope.status = 'iRacing'

    irUpdateTimeout = null

    authenticatedWatch = $scope.$watch 'authenticated', (n, o) ->
        if not n
            return
        authenticatedWatch()

        irWasConnected = false
        $scope.irUpdate = irUpdate = (force) ->
            if not $scope.ready or not $scope.authenticated or $scope.statusUpdating
                irUpdateTimeout = $timeout irUpdate, 1000
                return

            if ir.connected
                irWasConnected = true
                if not ir.DriverInfo or not ir.WeekendInfo
                    return
                # search for driverInfo
                for driverInfo in ir.DriverInfo.Drivers
                    if driverInfo.CarIdx == ir.DriverInfo.DriverCarIdx
                        break
                # remove open/lone from qualify
                sessionType = ir.SessionInfo.Sessions[ir.SessionInfo.Sessions.length - 1].SessionType
                if sessionType.indexOf(' ') != -1
                    sessionType = sessionType.split(' ')[1]
                # params for template
                params = [
                    sessionType
                    getCarName driverInfo.CarClassShortName, driverInfo.CarPath
                    ir.WeekendInfo.TrackDisplayName
                ]
                status = settings.connectedTmpl
                for v, i in params
                    status = status.split("{#{i}}").join v
                if status and (settings.autoUpdate or force)
                    updateStatus status
            else if (irWasConnected and settings.autoUpdate) or force
                status = settings.disconnectedTmpl
                if status
                    updateStatus status

        $scope.$watch 'ir.connected', -> irUpdate()
        $scope.$watch 'ir.DriverInfo', -> irUpdate()
        $scope.$watch 'ir.SessionInfo', -> irUpdate()
        $scope.$watch 'ir.WeekendInfo', -> irUpdate()

        if settings.showNewFollowers
            if not followers.length
                grabFollowers()
            else
                $interval.cancel updateTwitchFollowersInterval
                updateTwitchFollowersInterval = $interval updateTwitchFollowers, 5000

    getCarName = (name, path) ->
        if not name or name == 'Hosted All Cars'
            return path
        name

    # new followers
    $scope.showFollowers = showFollowers = []
    followers = []

    $scope.clickNewFollower = (follower) ->
        for f, i in showFollowers
            if f.name == follower.name
                index = i
                break
        if index >= 0
            showFollowers.splice index, 1

    $scope.testNewFollowerSound = ->
        newFollowerSound.currentTime = 0
        newFollowerSound.play()

    getFollowers = (limit, offset, success, error) ->
        $http.jsonp $sce.trustAsResourceUrl("#{baseUri}/channels/#{token.user_name}/follows"),
            params:
                oauth_token: settings.access_token
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
                    collectFollowersPagesLeft = Math.ceil response.data._total / limit
                    if response.data._total == 0 and response.data.follows.length != 0
                        $timeout ->
                            grabFollowers()
                        , 1000
                        return
                for f in response.data.follows
                    if f.user.name not in followers
                        followers.push f.user.name
                collectFollowersPagesLeft--
                if settings.showNewFollowers
                    if collectFollowersPagesLeft > 0
                        grabFollowers(page + 1, limit)
                    else
                        $interval.cancel updateTwitchFollowersInterval
                        updateTwitchFollowersInterval = $interval updateTwitchFollowers, 5000
            , (error) ->
                if error?.data?.message == 'Offset too high'
                    $interval.cancel updateTwitchFollowersInterval
                    updateTwitchFollowersInterval = $interval updateTwitchFollowers, 5000
                else
                    $timeout ->
                        grabFollowers page, limit
                    , 1000

    updateTwitchFollowers = -> getFollowers 5, 0, (response) ->
        if response.data.error?
            return

        # test
        # console.log response.data.follows[0]
        # f = response.data.follows[0].user
        # exist = false
        # for follower in showFollowers
        #     if f.name == follower.name
        #         exist = true
        #         return
        # if not exist
        #     showFollowers.push f
        #     newFollowerSound.play()

        if followers.length
            hasNewFollower = false
            for f in response.data.follows
                if f.user.name not in followers
                    followers.push f.user.name
                    showFollowers.push f.user
                    hasNewFollower = true

            sessionType = ir.SessionInfo and ir.SessionInfo.Sessions[ir.SessionNum].SessionType
            if hasNewFollower and newFollowerSound.volume > 0 and \
                    not (ir.IsOnTrack and \
                        settings.noSoundInRaceOrQual and \
                        ['Race', 'Lone Qualify', 'Open Qualify'].indexOf(sessionType) != -1)
                newFollowerSound.play()
                newFollowerSound.currentTime = 0
        else
            for f in response.data.follows
                followers.push f.user.name

    $scope.twitterShare = ->
        window.open \
            "https://twitter.com/intent/tweet\
                ?url=http://twitch.tv/#{$scope.userName}\
                &text=#{encodeURIComponent $scope.status}",
            '_blank',
            "left=#{screen.width - 500 >> 1},top=100,width=500,height=256"
        return

    $scope.$on '$destroy', ->
        $timeout.cancel toggleSettingsPanelTimeout
        $timeout.cancel getStatusTimeout
        $timeout.cancel updateStatusTimeout
        $timeout.cancel irUpdateTimeout
        $interval.cancel updateTwitchFollowersInterval

app.directive 'appIrStatus', (iRData) ->
    link: (scope, element, attrs) ->
        ir = iRData
        element.addClass 'label'
        scope.$watch 'authenticated', (n, o) ->
            element.toggleClass 'ng-hide', not n

        scope.$watch 'ir.connected', (n, o) ->
            carIdx = n
            element.text "iRacing status: #{if n then 'connected' else 'disconnected'}"
            element.toggleClass 'label-success', n
            element.toggleClass 'label-danger', not n

app.directive 'appTwitchStream', ($timeout) ->
    link: (scope, element, attrs) ->
        $(window).resize updateTwtichStreamSize = ->
            h = element.width() / 16 * 9
            console.log element.width(), h
            if h != element.height()
                element.height h

        firstResizeTimeout = $timeout updateTwtichStreamSize, 100

        scope.$on '$destroy', ->
            $timeout.cancel firstResizeTimeout

app.directive 'appTwitchChat', ->
    link: (scope, element, attrs) ->
        scope.$watch 'settings.showStream', (n, o) ->
            element.height if n then 335 else 500





angular.bootstrap document, [app.name]
