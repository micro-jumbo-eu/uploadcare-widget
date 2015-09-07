window.uploadcare ||= {}


uploadcare.namespace = (path, fn) ->
  target = uploadcare
  if path
    for part in path.split('.')
      target[part] ||= {}
      target = target[part]

  fn(target)


uploadcare.expose = (key, value) ->
  parts = key.split('.')
  last = parts.pop()

  target = window.uploadcare
  source = uploadcare

  for part in parts
    target[part] ||= {}
    target = target[part]
    source = source?[part]

  target[last] = value || source[last]
