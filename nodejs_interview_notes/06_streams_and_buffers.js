/*
===============================================================================================
                                  STREAMS and BUFFERS
===============================================================================================
Streams are a Node superpower and a frequent "do you really know Node?" question. Directly
relevant to my resume: the 2M-record EDI import is a textbook streaming + batching problem.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is a Buffer?
-----------------------------------------------------------------------------------------------
Answer -> A Buffer is Node's way of handling RAW BINARY data — a fixed-length chunk of memory
OUTSIDE the V8 heap. JavaScript strings are great for text but bad for binary (images, files,
network packets, encrypted bytes), so Node added Buffer (which today is a subclass of
Uint8Array).

  const buf = Buffer.from('hello', 'utf8');  // create from a string
  console.log(buf);                          // <Buffer 68 65 6c 6c 6f>  (hex bytes)
  console.log(buf.length);                   // 5 (bytes, not characters!)
  console.log(buf.toString('utf8'));         // 'hello'
  console.log(buf.toString('base64'));       // 'aGVsbG8='

  Buffer.alloc(10)        // 10 zero-filled bytes (safe)
  Buffer.allocUnsafe(10)  // faster but may contain old memory — overwrite before use

  Why it matters: file reads, TCP sockets, crypto, and stream chunks are all Buffers. "length"
  is BYTE length — a multi-byte UTF-8 char (é, emoji) is more than one byte, which causes bugs
  if you slice a buffer in the middle of a character.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: What is a Stream and why use it?
-----------------------------------------------------------------------------------------------
Answer -> A stream processes data PIECE BY PIECE (in chunks) instead of loading it all into
memory at once. This is essential for large data and for low-latency processing.

  THE KEY BENEFIT: memory efficiency + time efficiency.
   - Reading a 2GB file with fs.readFile loads all 2GB into RAM -> can crash the process.
   - Streaming reads it in ~64KB chunks -> constant low memory, and you can start processing
     the first chunk before the last one has even been read.

  Analogy: a stream is like watching a YouTube video (you start watching while it downloads)
  vs downloading the whole file before you can play it.

  // BAD for large files: buffers the whole thing in memory
  const data = fs.readFileSync('huge.csv');

  // GOOD: stream it, constant memory
  const rl = require('readline').createInterface({ input: fs.createReadStream('huge.csv') });
  for await (const line of rl) { processLine(line); }
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: The four types of streams
-----------------------------------------------------------------------------------------------
Answer ->
  1. Readable  -> you read FROM it. (fs.createReadStream, an HTTP request body, process.stdin)
  2. Writable  -> you write TO it.  (fs.createWriteStream, an HTTP response, process.stdout)
  3. Duplex    -> both readable AND writable, independent. (a TCP socket)
  4. Transform -> a duplex stream that MODIFIES data as it passes through.
                  (zlib.createGzip(), a CSV parser, an encryption stream)

  Streams emit events: 'data' (chunk available), 'end' (no more data), 'error', 'finish'
  (writable done), 'close'.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: pipe() and pipeline() — connecting streams
-----------------------------------------------------------------------------------------------
Answer -> pipe() connects a readable stream to a writable one and AUTOMATICALLY handles
backpressure (it pauses the source if the destination can't keep up).

  // Copy a file with streams + gzip it on the way (a Transform in the middle):
  const fs = require('fs');
  const zlib = require('zlib');
  fs.createReadStream('input.txt')
    .pipe(zlib.createGzip())          // transform
    .pipe(fs.createWriteStream('input.txt.gz'));

  PROBLEM with .pipe(): error handling is awkward — an error on one stream doesn't clean up
  the others, leaking file descriptors. PREFER stream.pipeline (handles errors + cleanup):

  const { pipeline } = require('stream/promises');
  await pipeline(
    fs.createReadStream('input.txt'),
    zlib.createGzip(),
    fs.createWriteStream('input.txt.gz')
  );   // rejects if any stage errors, and destroys all streams properly
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Backpressure — the concept that proves you understand streams
-----------------------------------------------------------------------------------------------
Answer -> Backpressure is what happens when a readable produces data FASTER than the writable
can consume it (e.g. reading from a fast disk, writing to a slow network/DB). Without handling
it, data piles up in memory until the process runs out of RAM.

How Node handles it:
  - writable.write(chunk) returns FALSE when its internal buffer is full ("please slow down").
  - The producer should then PAUSE until the writable emits a 'drain' event, then resume.
  - pipe() and pipeline() do this automatically — that's the main reason to use them instead
    of manually wiring 'data' -> write.

INTERVIEW SOUNDBITE:
  "Backpressure is the flow-control mechanism in streams. When the destination can't keep up,
   write() returns false and the source pauses until 'drain'. pipe/pipeline manage this for
   me, which is why streaming a huge file uses constant memory instead of blowing the heap."
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Real example — streaming an HTTP response (don't buffer big payloads)
-----------------------------------------------------------------------------------------------
Answer ->
  // Streaming a large file to the client without loading it into memory:
  app.get('/download/:file', (req, res) => {
    const path = safeJoin('/files', req.params.file);
    const stream = fs.createReadStream(path);
    stream.on('error', () => res.status(404).end('Not found'));
    res.setHeader('Content-Type', 'application/octet-stream');
    stream.pipe(res);   // client gets data as it's read; constant memory
  });

  // Streaming a DB export as CSV (e.g. with Sequelize/Knex cursor) avoids OOM on big tables.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: How streams connect to my Horizon EDI import story
-----------------------------------------------------------------------------------------------
Answer -> In Rails I cut a 2M-record import from 24h to 6min with Mongoid bulk upserts. The
Node version of that same story:

  "I'd stream the EDI file with createReadStream piped into a parser (Transform stream), so I
   never hold the whole file in memory. I'd accumulate records into batches of a few thousand,
   and for each batch run a single bulkWrite with ordered:false so independent docs don't block
   each other on a failure. Backpressure from the parser keeps memory flat, and I'd run the
   whole thing inside a BullMQ worker so it doesn't tie up the web process. The wins come from
   the same three levers as Rails: streaming (constant memory), batching, and bulk DB ops."

That answer maps my real, proven Rails optimization onto Node primitives — very convincing.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Quick gotchas
-----------------------------------------------------------------------------------------------
Answer ->
  - Always handle the 'error' event on a stream, or an error can crash the process.
  - Don't mix consuming a readable in flowing mode ('data' listener) and paused mode (.read()).
  - Buffer.length is in BYTES; don't slice across multi-byte UTF-8 chars (use string_decoder
    or process whole lines via readline).
  - For object data (not bytes), use objectMode streams (each chunk is a JS object/record).
  - process.stdout / process.stderr ARE writable streams; console.log writes to stdout.
*/

module.exports = {};
