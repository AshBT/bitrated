{ Transaction, Util: { parseValue, bytesToNum }, convert: { hexToBytes, bytesToHex, bytesToBase64, base64ToBytes } } = require 'bitcoinjs-lib'
{ sha256b, verify_sig, create_multisig } = require '../../../lib/bitcoin/index.coffee'
{ decode_raw_tx } = require '../../../lib/bitcoin/tx.coffee'

BLOCKCHAIN_API = $('meta[name=blockchain-api]').attr('content')

triple_sha256 = (bytes) -> sha256b sha256b sha256b bytes

get_socket = do (socket=null) -> -> socket ||= require('socket.io-client').connect '/', transports: ['xhr-polling']

# Create a deterministic channel name based on the public keys and terms
get_channel = ({ bob, alice, trent, terms }) ->
  # quick & dirty way to sort byte arrays
  ordered_parties = hexToBytes [bob, alice].map(bytesToHex).sort().join('')
  triple_sha256 [ ordered_parties..., trent..., terms... ]

# Listen for handshake replies
# Verifies the terms signature and checks the multisig address matches,
# which also ensures all the public keys matches
handshake_listen = (channel, { bob, trent, terms }, cb) ->
  channel = bytesToBase64 channel
  socket = get_socket()
  socket.emit 'join', channel
  socket.once channel, hs_cb = ({ pub: alice, proof, script_hash }, ack_id) ->
    # Sends errors to callback and to the other party (via the server)
    error_cb = (err) ->
      socket.emit ack_id, err
      cb err

    alice = base64ToBytes alice
    proof = base64ToBytes proof
    { script } = create_multisig [ bob, alice, trent ]
    expected_script_hash = bytesToBase64 triple_sha256 script.buffer

    if not verify_sig alice, terms, proof
      error_cb new Error 'Invalid terms signature'
    else if script_hash isnt expected_script_hash
      error_cb new Error 'Provided multisig script doesn\'t match'
    else
      do unlisten
      # notify success to the other party
      socket.emit ack_id, null, ->
        cb null, { alice, proof }
  unlisten = ->
    socket.emit 'part', channel
    socket.removeListener channel, hs_cb

# Send handshake reply
handshake_reply = (channel, { pub, proof, script }, cb) ->
  channel = bytesToBase64 channel
  get_socket().emit 'handshake', channel, {
    pub: bytesToBase64 pub
    proof: bytesToBase64 proof
    script_hash: bytesToBase64 triple_sha256 script.buffer
  }, cb

# Listen for incoming transaction
tx_listen = (channel, cb) ->
  channel = bytesToBase64 channel
  socket = get_socket()
  socket.emit 'join', channel
  socket.on channel, tx_cb = (base64tx) ->
    # TODO load total inputs balance
    cb decode_raw_tx base64ToBytes base64tx
  unlisten = ->
    socket.emit 'part', channel
    socket.removeListener 'tx:'+channel, tx_cb

# Send transaction request
tx_request = (channel, tx, cb) ->
  channel = bytesToBase64 channel
  tx = bytesToBase64 tx.serialize()
  get_socket().emit 'msg', channel, tx
  cb null

# Send transaction to Bitcoin network using blockchain.info's pushtx
tx_broadcast = (tx, cb) ->
  tx = bytesToHex tx.serialize()
  $.post(BLOCKCHAIN_API + 'pushtx', { tx })
    .fail((xhr, status, err) -> cb "Cannot pushtx: #{ xhr.responseText or err }")
    .done((data) -> cb null, data)

# Load unspent inputs (from blockchain.info)
load_unspent = (address, cb) ->
  xhr = $.get BLOCKCHAIN_API + "unspent/#{address}"
  xhr.done (res) ->
      unspent = for { txid, n, value, script } in res
        { hash: txid, index: n, value, script }
      cb null, unspent
  xhr.fail (xhr, status,err) -> cb new Error "Cannot load unspent inputs: #{ xhr.responseText or err}"

module.exports = {
  get_channel
  handshake_listen, handshake_reply
  tx_listen, tx_request
  load_unspent, tx_broadcast
}
