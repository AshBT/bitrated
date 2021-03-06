{ convert: { bytesToBase64, base64ToBytes } } = require 'bitcoinjs-lib'
{ iferr, extend } = require '../../lib/util.coffee'
qs = require 'querystring'

DEBUG = /(^|&)DEBUG(&|$)/.test location.hash.substr(1)
BASE = $('base[href]').attr('href') or throw new Error 'Missing <base>'

# Right/left pad
lpad = (bytes, len) -> bytes.unshift 0x00 while bytes.length<len; bytes
rpad = (bytes, len) -> bytes.push    0x00 while bytes.length<len; bytes

# given a container element, returns a function that displays an error in it
error_displayer = (container) -> (e) ->
  unless (el = container.find '.error').length
    el = $(document.createElement 'div')
      .addClass('error alert alert-error')
      .append('<button type="button" class="close" data-dismiss="alert">&times;</button>')
      .append('<p></p>')
      .prependTo(container)
  message = switch e.name
    when 'InvalidCharacterError' then 'Invalid input string provided.'
    else e.message ? e
  el.find('p').text(message).end().show()
  throw e if DEBUG

# Parse base64-encoded query string
parse_query = (str=document.location.hash.substr(1)) ->
  query = qs.parse str
  # Firefox decodes the hash, making the qs.parse() call decode it twice,
  # making "%2B" parse as a space. Replacing this back to a plus sign
  # makes it work on Firefox.
  query[k] = base64ToBytes v.replace(/( )/g, '+') for k, v of query when v.length
  query

# Create query string for the given data, with base64 encoding
format_url = (page, data={}) ->
  query = {}

  # Prefix URLs that contains private keys with "DO-NOT-SHARE"
  if data.bob_priv? or data.key_priv?
    query['DO-NOT-SHARE'] = null

  for name, val of data when val?
    val = bytesToBase64 val if Array.isArray val
    query[name] = val
  (if page? then BASE+page+'#' else '') + qs.stringify query

# Navigate to page
navto = (page, data) -> document.location = format_url page, data

# success(message) returns a function that dispalys the message
success = do (view = require '../views/dialog-success.jade') -> (message) -> ->
  dialog = $ view { message }
  dialog.on 'hidden', -> do dialog.remove
  dialog.modal()

# Render an element as the primary content
render = do ($root = $ '.content') -> (el) ->
  $root.empty().append(el)
  el.find('[data-toggle=tooltip]').tooltip()
  el.find('[data-toggle=popover]').popover()

module.exports = {
  lpad, rpad, extend
  iferr, error_displayer
  parse_query, format_url, navto, success, render
}
