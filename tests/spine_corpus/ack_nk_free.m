|| ackermann's function, without n+k patterns.
||
|| miralib/ex/ack.m uses `ack (m+1) 0 = ...` / `ack (m+1) (n+1) = ...` (n+k
|| patterns), which this interpreter currently fails to compile ("illegal
|| object \"1\" as head of formal") -- a genuine, pre-existing parser/compiler
|| limitation, unrelated to the reducer's spine encoding. tests/golden's
|| custom_ack.m sidesteps it the same way; this is that style, kept here so
|| the spine differential corpus has an ack.m-equivalent to run.

ack 0 n = n + 1
ack m 0 = ack (m - 1) 1
ack m n = ack (m - 1) (ack m (n - 1))
