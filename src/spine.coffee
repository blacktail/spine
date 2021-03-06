Events =
  bind: (ev, callback) ->
    evs   = ev.split(' ')
    calls = @hasOwnProperty('_callbacks') and @_callbacks or= {}
    for name in evs
      calls[name] or= []
      calls[name].push(callback)
    this
  
  one: (ev, callback) ->
    @bind ev, ->
      @unbind(ev, arguments.callee)
      callback.apply(this, arguments)
  
  trigger: (args...) ->
    ev = args.shift()
    list = @hasOwnProperty('_callbacks') and @_callbacks?[ev]
    return unless list
    for callback in list
      if callback.apply(this, args) is false
        break
    true
  
  listenTo: (obj, ev, callback) ->
    obj.bind(ev, callback)
    @listeningTo or= []
    @listeningTo.push obj
    this
  
  listenToOnce: (obj, ev, callback) ->
    obj.one(ev, callback)
    this
    
  stopListening: (obj, ev, callback) ->
    if obj
      obj.unbind(ev, callback)
      idx = @listeningTo.indexOf(obj)
      @listeningTo.splice(idx, 1) unless idx is -1
    else
      for obj in @listeningTo
        obj.unbind()
      @listeningTo = undefined
  
  unbind: (ev, callback) ->
    unless ev
      @_callbacks = {}
      return this
    evs  = ev.split(' ')
    for name in evs
      list = @_callbacks?[name]
      continue unless list
      unless callback
        delete @_callbacks[name]
        continue
      for cb, i in list when (cb is callback)
        list = list.slice()
        list.splice(i, 1)
        @_callbacks[name] = list
        break
    this

Events.on = Events.bind
Events.off = Events.unbind

Log =
  trace: true

  logPrefix: '(App)'

  log: (args...) ->
    return unless @trace
    if @logPrefix then args.unshift(@logPrefix)
    console?.log?(args...)
    this

moduleKeywords = ['included', 'extended']

class Module
  @include: (obj) ->
    throw new Error('include(obj) requires obj') unless obj
    for key, value of obj when key not in moduleKeywords
      @::[key] = value
    obj.included?.apply(this)
    this

  @extend: (obj) ->
    throw new Error('extend(obj) requires obj') unless obj
    for key, value of obj when key not in moduleKeywords
      @[key] = value
    obj.extended?.apply(this)
    this

  @proxy: (func) ->
    => func.apply(this, arguments)

  proxy: (func) ->
    => func.apply(this, arguments)

  constructor: ->
    @init?(arguments...)

class Model extends Module
  @extend Events

  @records: {}
  @crecords: {}
  @attributes: []

  @configure: (name, attributes...) ->
    @className  = name
    @records    = {}
    @crecords   = {}
    @attributes = attributes if attributes.length
    @attributes and= makeArray(@attributes)
    @attributes or=  []
    @unbind()
    this

  @toString: -> "#{@className}(#{@attributes.join(", ")})"

  @find: (id) ->
    throw new Error("\"#{@className}\" model could not find a record for the ID \"#{id}\"") unless @exists(id)
    record = @records[id] or @crecords[id]
    record.clone()

  @exists: (id) ->
    id of @records or id of @crecords

  @refresh: (values, options = {}) ->
    if options.clear
      @records  = {}
      @crecords = {}

    records = @fromJSON(values)
    records = [records] unless isArray(records)

    for record in records
      record.id           or= record.cid
      @records[record.id]   = record
      @crecords[record.cid] = record

    @trigger('refresh', @cloneArray(records))
    this

  @select: (callback) ->
    result = (record for id, record of @records when callback(record))
    @cloneArray(result)

  @findByAttribute: (name, value) ->
    for id, record of @records
      if record[name] is value
        return record.clone()
    null

  @findAllByAttribute: (name, value) ->
    @select (item) ->
      item[name] is value

  @each: (callback) ->
    for key, value of @records
      callback(value.clone())

  @all: ->
    @cloneArray(@recordsValues())

  @first: ->
    record = @recordsValues()[0]
    record?.clone()

  @last: ->
    values = @recordsValues()
    record = values[values.length - 1]
    record?.clone()

  @count: ->
    @recordsValues().length

  @deleteAll: ->
    for key, value of @records
      delete @records[key]

  @destroyAll: (options) ->
    for key, value of @records
      @records[key].destroy(options)

  @update: (id, atts, options) ->
    @find(id).updateAttributes(atts, options)

  @create: (atts, options) ->
    record = new @(atts)
    record.save(options)

  @destroy: (id, options) ->
    @find(id).destroy(options)

  @change: (callbackOrParams) ->
    if typeof callbackOrParams is 'function'
      @bind('change', callbackOrParams)
    else
      @trigger('change', callbackOrParams)

  @fetch: (callbackOrParams) ->
    if typeof callbackOrParams is 'function'
      @bind('fetch', callbackOrParams)
    else
      @trigger('fetch', callbackOrParams)

  @toJSON: ->
    @recordsValues()

  @fromJSON: (objects) ->
    return unless objects
    if typeof objects is 'string'
      objects = JSON.parse(objects)
    if isArray(objects)
      (new @(value) for value in objects)
    else
      new @(objects)

  @fromForm: ->
    (new this).fromForm(arguments...)

  # Private

  @recordsValues: ->
    result = []
    for key, value of @records
      result.push(value)
    result

  @cloneArray: (array) ->
    (value.clone() for value in array)

  @idCounter: 0

  @uid: (prefix = '') ->
    uid = prefix + @idCounter++
    uid = @uid(prefix) if @exists(uid)
    uid

  # Instance

  constructor: (atts) ->
    super
    @load atts if atts
    @cid = @constructor.uid('c-')

  isNew: ->
    not @exists()

  isValid: ->
    not @validate()

  validate: ->

  load: (atts) ->
    for key, value of atts
      if typeof @[key] is 'function'
        @[key](value)
      else
        @[key] = value
    this

  attributes: ->
    result = {}
    for key in @constructor.attributes when key of this
      if typeof @[key] is 'function'
        result[key] = @[key]()
      else
        result[key] = @[key]
    result.id = @id if @id
    result

  eql: (rec) ->
    !!(rec and rec.constructor is @constructor and
        (rec.cid is @cid) or (rec.id and rec.id is @id))

  save: (options = {}) ->
    unless options.validate is false
      error = @validate()
      if error
        @trigger('error', error)
        return false

    @trigger('beforeSave', options)
    record = if @isNew() then @create(options) else @update(options)
    @stripCloneAttrs()
    @trigger('save', options)
    record

  stripCloneAttrs: ->
    return if @hasOwnProperty 'cid' # Make sure it's not the raw object
    for own key, value of @
      delete @[key] if @constructor.attributes.indexOf(key) > -1
    this

  updateAttribute: (name, value, options) ->
    atts = {}
    atts[name] = value
    @updateAttributes(atts, options)

  updateAttributes: (atts, options) ->
    @load(atts)
    @save(options)

  changeID: (id) ->
    records = @constructor.records
    records[id] = records[@id]
    delete records[@id]
    @id = id
    @save()

  destroy: (options = {}) ->
    @trigger('beforeDestroy', options)
    delete @constructor.records[@id]
    delete @constructor.crecords[@cid]
    @destroyed = true
    @trigger('destroy', options)
    @trigger('change', 'destroy', options)
    if @listeningTo
      @stopListening()
    @unbind()
    this

  dup: (newRecord) ->
    result = new @constructor(@attributes())
    if newRecord is false
      result.cid = @cid
    else
      delete result.id
    result

  clone: ->
    createObject(this)

  reload: ->
    return this if @isNew()
    original = @constructor.find(@id)
    @load(original.attributes())
    original

  toJSON: ->
    @attributes()

  toString: ->
    "<#{@constructor.className} (#{JSON.stringify(this)})>"

  fromForm: (form) ->
    result = {}
    for key in $(form).serializeArray()
      result[key.name] = key.value
    @load(result)

  exists: ->
    @constructor.exists(@id)

  # Private

  update: (options) ->
    @trigger('beforeUpdate', options)
    records = @constructor.records
    records[@id].load @attributes()
    clone = records[@id].clone()
    clone.trigger('update', options)
    clone.trigger('change', 'update', options)
    clone

  create: (options) ->
    @trigger('beforeCreate', options)
    @id          = @cid unless @id

    record       = @dup(false)
    @constructor.records[@id]   = record
    @constructor.crecords[@cid] = record

    clone        = record.clone()
    clone.trigger('create', options)
    clone.trigger('change', 'create', options)
    clone

  bind: (events, callback) ->
    @constructor.bind events, binder = (record) =>
      if record && @eql(record)
        callback.apply(this, arguments)
    # create a wrapper function to be called with 'unbind' for each event 
    for singleEvent in events.split(' ') 
      do (singleEvent) =>
        @constructor.bind "unbind", unbinder = (record, event, cb) =>
          if record && @eql(record)
            return if event and event isnt singleEvent
            return if cb and cb isnt callback
            @constructor.unbind(singleEvent, binder)
            @constructor.unbind("unbind", unbinder)
    this

  one: (events, callback) ->
    @bind events, =>
      @unbind(events, arguments.callee)
      callback.apply(this, arguments)

  trigger: (args...) ->
    args.splice(1, 0, this)
    @constructor.trigger(args...)
  
  listenTo: (obj, events, callback) ->
    obj.bind events, callback
    @listeningTo or= []
    @listeningTo.push(obj)
  
  listenToOnce: (obj, events, callback) ->
    obj.bind events, =>
      obj.unbind(events, arguments.callee)
      callback.apply(obj, arguments)
  
  stopListening: (obj, events, callback) ->
    if obj
      obj.unbind events, callback
      idx = @listeningTo.indexOf(obj)
      @listeningTo.splice(idx, 1) unless idx is -1
    else
      for obj in @listeningTo
        obj.unbind()
      @listeningTo = undefined

  unbind: (events, callback) ->
    if events
      for event in events.split(' ') 
        @trigger('unbind', event, callback)
    else
      @trigger('unbind')

Model::on = Model::bind
Model::off = Model::unbind

class Controller extends Module
  @include Events
  @include Log

  eventSplitter: /^(\S+)\s*(.*)$/
  tag: 'div'

  constructor: (options) ->
    @options = options

    for key, value of @options
      @[key] = value

    @el  = document.createElement(@tag) unless @el
    @el  = $(@el)
    @$el = @el

    @el.addClass(@className) if @className
    @el.attr(@attributes) if @attributes

    @events = @constructor.events unless @events
    @elements = @constructor.elements unless @elements

    @delegateEvents(@events) if @events
    @refreshElements() if @elements

    super

  release: =>
    @trigger 'release'
    @el.remove()
    @unbind()
    if @listeningTo
      @stopListening()

  $: (selector) -> $(selector, @el)

  delegateEvents: (events) ->
    for key, method of events

      if typeof(method) is 'function'
        # Always return true from event handlers
        method = do (method) => =>
          method.apply(this, arguments)
          true
      else
        unless @[method]
          throw new Error("#{method} doesn't exist")

        method = do (method) => =>
          @[method].apply(this, arguments)
          true

      match      = key.match(@eventSplitter)
      eventName  = match[1]
      selector   = match[2]

      if selector is ''
        @el.bind(eventName, method)
      else
        @el.delegate(selector, eventName, method)

  refreshElements: ->
    for key, value of @elements
      @[value] = @$(key)

  delay: (func, timeout) ->
    setTimeout(@proxy(func), timeout || 0)

  html: (element) ->
    @el.html(element.el or element)
    @refreshElements()
    @el

  append: (elements...) ->
    elements = (e.el or e for e in elements)
    @el.append(elements...)
    @refreshElements()
    @el

  appendTo: (element) ->
    @el.appendTo(element.el or element)
    @refreshElements()
    @el

  prepend: (elements...) ->
    elements = (e.el or e for e in elements)
    @el.prepend(elements...)
    @refreshElements()
    @el

  replace: (element) ->
    [previous, @el] = [@el, $(element.el or element)]
    previous.replaceWith(@el)
    @delegateEvents(@events)
    @refreshElements()
    @el

# Utilities & Shims

$ = window?.jQuery or window?.Zepto or (element) -> element

createObject = Object.create or (o) ->
  Func = ->
  Func.prototype = o
  new Func()

isArray = (value) ->
  Object::toString.call(value) is '[object Array]'

isBlank = (value) ->
  return true unless value
  return false for key of value
  true

makeArray = (args) ->
  Array::slice.call(args, 0)

# Globals

Spine = @Spine   = {}
module?.exports  = Spine

Spine.version    = '1.0.9'
Spine.isArray    = isArray
Spine.isBlank    = isBlank
Spine.$          = $
Spine.Events     = Events
Spine.Log        = Log
Spine.Module     = Module
Spine.Controller = Controller
Spine.Model      = Model

# Global events

Module.extend.call(Spine, Events)

# JavaScript compatability

Module.create = Module.sub =
  Controller.create = Controller.sub =
    Model.sub = (instances, statics) ->
      class Result extends this
      Result.include(instances) if instances
      Result.extend(statics) if statics
      Result.unbind?()
      Result

Model.setup = (name, attributes = []) ->
  class Instance extends this
  Instance.configure(name, attributes...)
  Instance

Spine.Class = Module
