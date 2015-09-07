# = require uploadcare/utils/pusher

{
  jQuery: $,
  utils
} = uploadcare
{pusher} = uploadcare.utils

uploadcare.namespace 'files', (ns) ->

  class ns.UrlFile extends ns.BaseFile
    allEvents: 'progress success error fail'

    constructor: (settings, @__url) ->
      super

      filename = utils.splitUrlRegex.exec(@__url)[3].split('/').pop()
      if filename
        try
          @fileName = decodeURIComponent(filename)
        catch err
          @fileName = filename

      @__notifyApi()

    setName: (@fileName) ->
      @__realFileName = fileName
      @__notifyApi()

    setIsImage: (@isImage) ->
      @__notifyApi()

    setSourceInfo: (@sourceInfo) ->
      @__notifyApi()

    __startUpload: ->
      df = $.Deferred()
      pusherWatcher = new PusherWatcher(@settings.pusherKey)
      pollWatcher = new PollWatcher("#{@settings.urlBase}/from_url/status/")

      data =
        pub_key: @settings.publicKey
        source_url: @__url
        filename: @__realFileName or ''
        store: if @settings.doNotStore then '' else 'auto'

      utils.jsonp("#{@settings.urlBase}/from_url/", data)
        .fail(df.reject)
        .done (data) =>
          @__listenWatcher(df, $([pusherWatcher, pollWatcher]))
          df.always =>
            $([pusherWatcher, pollWatcher]).off(@allEvents)
            pusherWatcher.stopWatching()
            pollWatcher.stopWatching()

          # turn off pollWatcher if we receive any message from pusher
          $(pusherWatcher).one @allEvents, =>
            pollWatcher.stopWatching()

          pusherWatcher.watch(data.token)
          pollWatcher.watch(data.token)

      df

    __listenWatcher: (df, watcher) =>
      watcher
        .on 'progress', (e, data) =>
          @fileSize = data.total
          df.notify(data.done / data.total)

        .on 'success', (e, data) =>
          $(e.target).trigger('progress', data)
          @fileId = data.uuid
          @fileName = data.original_filename
          df.resolve()

        .on('error fail', df.reject)


  class PusherWatcher
    constructor: (pusherKey) ->
      @pusher = pusher.getPusher(pusherKey)

    watch: (@token) ->
      channel = @pusher.subscribe("task-status-#{@token}")

      channel.bind_all (ev, data) =>
        $(this).trigger(ev, data)

    stopWatching: ->
      @pusher.unsubscribe("task-status-#{@token}")


  class PollWatcher
    constructor: (@poolUrl) ->

    watch: (@token) ->
      do bind = =>
        @interval = setTimeout( =>
          @__updateStatus().done =>
            if @interval  # Do not schedule next request if watcher stopped.
              bind()
        , 333)

    stopWatching: ->
      if @interval
        clearTimeout(@interval)
      @interval = null

    __updateStatus: ->
      utils.jsonp(@poolUrl, {@token})
        .fail (error) =>
          $(this).trigger('error')
        .done (data) =>
          $(this).trigger(data.status, data)
