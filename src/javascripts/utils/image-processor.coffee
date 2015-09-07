{
  jQuery: $,
  utils,
} = uploadcare

uploadcare.namespace 'utils.imageProcessor', (ns) ->

  DataView = window.DataView
  FileReader = window.FileReader?.prototype.readAsArrayBuffer && window.FileReader
  URL = window.URL or window.webkitURL
  URL = URL && URL.createObjectURL && URL
  Blob = utils.abilities.blob && window.Blob

  taskRunner = utils.taskRunner(1)

  ns.shrinkFile = (file, settings) ->
    # in -> file
    # out <- blob
    df = $.Deferred()

    if not (URL and DataView and Blob)
      return df.reject('support')

    # start = new Date()
    taskRunner (release) =>
      # console.log('delayed: ' + (new Date() - start))
      df.always(release)

      # start = new Date()
      img = new Image()
      img.onerror = ->
          df.reject('not image')
      img.onload = ->
        # console.log('load: ' + (new Date() - start))
        URL.revokeObjectURL(img.src)
        img.onerror = null  # do not fire when set to blank
        df.notify(.10)

        exif = null
        op = ns.readJpegChunks(file)
        op.progress (pos, length, marker, view) ->
          if not exif and marker == 0xe1
            if view.byteLength >= 14
              if view.getUint32(0) == 0x45786966 and view.getUint16(4) == 0
                exif = view.buffer
        op.always ->
          df.notify(.2)
          isJPEG = op.state() is 'resolved'

          op = ns.shrinkImage(img, settings)
          op.progress (progress) ->
            df.notify(.2 + progress * .6)
          op.fail(df.reject)
          op.done (canvas) ->
            # start = new Date()
            format = 'image/jpeg'
            quality = settings.quality or 0.8
            if not isJPEG and ns.hasTransparency(canvas)
              format = 'image/png'
              quality = undefined
            utils.canvasToBlob canvas, format, quality,
              (blob) ->
                canvas.width = canvas.height = 1
                df.notify(.9)
                # console.log('to blob: ' + (new Date() - start))
                if exif
                  op = ns.replaceJpegChunk(blob, 0xe1, [exif])
                  op.done(df.resolve)
                  op.fail ->
                    df.resolve(blob)
                else
                  df.resolve(blob)
          img = null  # free reference

      img.src = URL.createObjectURL(file)

    df.promise()


  ns.shrinkImage = (img, settings) ->
    # in -> image
    # out <- canvas
    df = $.Deferred()

    step = 0.71  # sohuld be > sqrt(0.5)

    if img.width * step * img.height * step < settings.size
      return df.reject('not required')

    # start = new Date()
    sW = originalW = img.width
    sH = img.height
    ratio = sW / sH
    w = Math.floor(Math.sqrt(settings.size * ratio))
    h = Math.floor(settings.size / Math.sqrt(settings.size * ratio))

    maxSquare = 5000000  # ios max canvas square
    maxSize = 4096  # ie max canvas dimensions

    do run = ->
      if sW <= w
        # console.log('draw: ' + (new Date() - start))
        df.resolve(img)
        return

      utils.defer ->
        sW = Math.round(sW * step)
        sH = Math.round(sH * step)
        if sW * step < w
          sW = w
          sH = h
        if sW * sH > maxSquare
          sW = Math.floor(Math.sqrt(maxSquare * ratio))
          sH = Math.floor(maxSquare / Math.sqrt(maxSquare * ratio))
        if sW > maxSize
          sW = maxSize
          sH = Math.round(sW / ratio)
        if sH > maxSize
          sH = maxSize
          sW = Math.round(ratio * sH)
        canvas = document.createElement('canvas')
        canvas.width = sW
        canvas.height = sH
        canvas.getContext('2d').drawImage(img, 0, 0, sW, sH)
        img.src = '//:0'            # for image
        img.width = img.height = 1  # for canvas
        img = canvas

        df.notify((originalW - sW) / (originalW - w))
        run()

    df.promise()


  ns.readJpegChunks = (file) ->
    readToView = (file, cb) ->
      reader = new FileReader()
      reader.onload = ->
        cb(new DataView(reader.result))
      reader.onerror = (e) ->
        df.reject('reader', e)
      reader.readAsArrayBuffer(file)

    readNext = ->
      readToView file.slice(pos, pos + 128), (view) ->
        for i in [0...view.byteLength]
          if view.getUint8(i) == 0xff
            pos += i
            break
        readNextChunk()

    readNextChunk = ->
      startPos = pos
      readToView file.slice(pos, pos += 4), (view) ->
        if view.byteLength != 4 or view.getUint8(0) != 0xff
          return df.reject('corrupted')

        marker = view.getUint8(1)
        if marker == 0xda # Start Of Scan
          # console.log('read jpeg chunks: ' + (new Date() - start))
          return df.resolve()
        length = view.getUint16(2) - 2

        readToView file.slice(pos, pos += length), (view) ->
          if view.byteLength != length
            return df.reject('corrupted')
          df.notify(startPos, length, marker, view)
          readNext()

    df = $.Deferred()

    if not (FileReader and DataView)
      return df.reject('support')

    # start = new Date()
    pos = 2

    readToView file.slice(0, 2), (view) ->
      if view.getUint16(0) != 0xffd8
        return df.reject('not jpeg')
      readNext()

    df.promise()


  ns.replaceJpegChunk = (blob, marker, chunks) ->
    df = $.Deferred()
    oldChunkPos = []
    oldChunkLength = []

    op = ns.readJpegChunks(blob)
    op.fail(df.reject)
    op.progress (pos, length, oldMarker) ->
      if oldMarker == marker
        oldChunkPos.push(pos)
        oldChunkLength.push(length)
    op.done ->
      newChunks = [blob.slice(0, 2)]
      for chunk in chunks
        intro = new DataView(new ArrayBuffer(4))
        intro.setUint16(0, 0xff00 + marker)
        intro.setUint16(2, chunk.byteLength + 2)
        newChunks.push(intro.buffer)
        newChunks.push(chunk)

      pos = 2
      for i in [0...oldChunkPos.length]
        if oldChunkPos[i] > pos
          newChunks.push(blob.slice(pos, oldChunkPos[i]))
        pos = oldChunkPos[i] + oldChunkLength[i] + 4
      newChunks.push(blob.slice(pos, blob.size))

      df.resolve(new Blob(newChunks, {type: blob.type}))

    df.promise()


  ns.hasTransparency = (img) ->
    pcsn = 50

    canvas = document.createElement('canvas')
    canvas.width = canvas.height = pcsn
    ctx = canvas.getContext('2d')
    ctx.drawImage(img, 0, 0, pcsn, pcsn)
    data = ctx.getImageData(0, 0, pcsn, pcsn).data
    canvas.width = canvas.height = 1

    for i in [3...data.length] by 4
      if data[i] < 254
        return true

    return false
