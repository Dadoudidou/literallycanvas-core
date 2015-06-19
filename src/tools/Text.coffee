{Tool} = require './base'
{createShape} = require '../core/shapes'


getIsPointInBox = (point, box) ->
  if point.x < box.x then return false
  if point.y < box.y then return false
  if point.x > box.x + box.width then return false
  if point.y > box.y + box.height then return false
  return true


module.exports = class Text extends Tool

  name: 'Text'
  iconName: 'text'

  constructor: (@text = '', @font = 'bold 18px sans-serif') ->
    @currentShape = null
    @currentShapeState = null
    @initialShapeBoundingRect = null
    @dragAction = null
    @didDrag = false

  setText: (text) ->
    @text = text

  commit: (lc) ->
    @initialShapeBoundingRect = null
    @currentShapeState = null
    lc.saveShape(@currentShape)
    lc.setShapesInProgress([])
    lc.repaintLayer('main')
    @currentShape = null

  _getSelectionShape: (ctx, backgroundColor=null) ->
    createShape('SelectionBox', {
      shape: @currentShape, ctx: lc.ctx, backgroundColor
    })

  _setShapesInProgress: (lc) ->
    switch @currentShapeState
      when 'selected'
        lc.setShapesInProgress([@_getSelectionShape(lc.ctx), @currentShape])
      when 'editing'
        lc.setShapesInProgress([@_getSelectionShape(lc.ctx, '#fff')])
      else
        lc.setShapesInProgress([@currentShape])

  begin:(x, y, lc) ->
    @dragAction = 'none'
    @didDrag = false

    if (@currentShapeState == 'selected' or @currentShapeState == 'editing')
      br = @currentShape.getBoundingRect(lc.ctx)
      selectionShape = @_getSelectionShape(lc.ctx)
      selectionBox = selectionShape.getBoundingRect()
      point = {x, y}
      if getIsPointInBox(point, br)
        @dragAction = 'move'
      if getIsPointInBox(point, selectionShape.getBottomRightHandleRect())
        @dragAction = 'resizeBottomRight'
      if getIsPointInBox(point, selectionShape.getTopLeftHandleRect())
        @dragAction = 'resizeTopLeft'
      if getIsPointInBox(point, selectionShape.getBottomLeftHandleRect())
        @dragAction = 'resizeBottomLeft'
      if getIsPointInBox(point, selectionShape.getTopRightHandleRect())
        @dragAction = 'resizeTopRight'

      if @dragAction == 'none' and @currentShapeState == 'editing'
        @dragAction = 'stop-editing'
        @_exitEditingState(lc)
    else
      @color = lc.getColor('primary')
      @currentShape = createShape('Text', {x, y, @text, @color, @font, v: 1})
      @dragAction = 'place'
      @currentShapeState = 'selected'

    if @dragAction == 'none'
      @commit(lc)
      return

    @initialShapeBoundingRect = @currentShape.getBoundingRect(lc.ctx)
    @dragOffset = {
      x: x - @initialShapeBoundingRect.x,
      y: y - @initialShapeBoundingRect.y
    }

    @_setShapesInProgress(lc)
    lc.repaintLayer('main')

  continue:(x, y, lc) ->
    if @dragAction == 'none'
      return

    br = @initialShapeBoundingRect
    brRight = br.x + br.width
    brBottom = br.y + br.height
    switch @dragAction
      when 'place'
        @currentShape.x = x
        @currentShape.y = y
        @didDrag = true
      when 'move'
        @currentShape.x = x - @dragOffset.x
        @currentShape.y = y - @dragOffset.y
        @didDrag = true
      when 'resizeBottomRight'
        @currentShape.setSize(
          x - (@dragOffset.x - @initialShapeBoundingRect.width) - br.x,
          y - (@dragOffset.y - @initialShapeBoundingRect.height) - br.y)
      when 'resizeTopLeft'
        @currentShape.setSize(
          brRight - x + @dragOffset.x,
          brBottom - y + @dragOffset.y)
        @currentShape.setPosition(x - @dragOffset.x, y - @dragOffset.y)
      when 'resizeBottomLeft'
        @currentShape.setSize(
          brRight - x + @dragOffset.x,
          y - (@dragOffset.y - @initialShapeBoundingRect.height) - br.y)
        @currentShape.setPosition(x - @dragOffset.x, @currentShape. y)
      when 'resizeTopRight'
        @currentShape.setSize(
          x - (@dragOffset.x - @initialShapeBoundingRect.width) - br.x,
          brBottom - y + @dragOffset.y)
        @currentShape.setPosition(@currentShape.x, y - @dragOffset.y)

    @_setShapesInProgress(lc)
    lc.repaintLayer('main')

    @_updateInputEl(lc)

  end:(x, y, lc) ->
    return unless @currentShape  # we may have committed at start time

    # use auto height once user lets go of selection corner
    @currentShape.setSize(@currentShape.forcedWidth, 0)

    if @currentShapeState == 'selected'
      if @dragAction == 'place' or (@dragAction == 'move' and not @didDrag)
        @_enterEditingState(lc)

    @_setShapesInProgress(lc)
    lc.repaintLayer('main')
    @_updateInputEl(lc)

  _enterEditingState: (lc) ->
    @currentShapeState = 'editing'

    throw "State error" if @inputEl

    @inputEl = document.createElement('textarea')
    @inputEl.className = 'text-tool-input'
    @inputEl.style.position = 'absolute'
    @inputEl.style.transformOrigin = '0px 0px'
    @inputEl.style.backgroundColor = 'transparent'
    @inputEl.style.border = 'none'
    @inputEl.style.outline = 'none'
    @inputEl.style.margin = '0'
    @inputEl.style.padding = '4px'
    @inputEl.style.zIndex = '1000'
    @inputEl.style.overflow = 'hidden'
    @inputEl.style.resize = 'none'

    @inputEl.value = @currentShape.text

    @inputEl.addEventListener 'mousedown', (e) -> e.stopPropagation()
    @inputEl.addEventListener 'touchstart', (e) -> e.stopPropagation()

    onChange = (e) =>
      @currentShape.setText(e.target.value)
      @_setShapesInProgress(lc)
      lc.repaintLayer('main')
      @_updateInputEl(lc)
      e.stopPropagation()

    @inputEl.addEventListener 'keydown', => @_updateInputEl(lc, true)
    @inputEl.addEventListener 'keyup', onChange
    @inputEl.addEventListener 'change', onChange

    @_updateInputEl(lc)

    lc.containerEl.appendChild(@inputEl)
    @inputEl.focus()

    @_setShapesInProgress(lc)

  _exitEditingState: (lc) ->
    @currentShapeState = 'selected'
    lc.containerEl.removeChild(@inputEl)
    @inputEl = null

    @_setShapesInProgress(lc)
    lc.repaintLayer('main')

  _updateInputEl: (lc, withMargin=false) ->
    return unless @inputEl
    br = @currentShape.getBoundingRect(lc.ctx)
    @inputEl.style.font = @currentShape.font
    @inputEl.style.left = "#{lc.position.x / lc.getRenderScale() + br.x - 4}px"
    @inputEl.style.top = "#{lc.position.y / lc.getRenderScale() + br.y - 4}px"
    if withMargin
      @inputEl.style.width =
        "#{br.width + 10 + @currentShape.renderer.emDashWidth}px"
    else
      @inputEl.style.width = "#{br.width + 10}px"
    @inputEl.style.height =
      "#{br.height + 10 + @currentShape.renderer.metrics.leading}px"
    scalePercent = "#{lc.scale * 100}%"
    @inputEl.style.transformScale = "#{scalePercent} #{scalePercent}"

  optionsStyle: 'font'
