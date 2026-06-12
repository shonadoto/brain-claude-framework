#!/usr/bin/env bash
# PreCompact: перед сжатием контекста напомнить агенту слить незаписанные решения в journal задачи.
jq -n '{hookSpecificOutput:{hookEventName:"PreCompact",additionalContext:"Контекст сейчас будет сжат. Если в сессии есть решения, тупики или внешние факты, ещё не записанные в tasks/<task>/journal.md — допиши их СЕЙЧАС (журналирование по ходу, CONVENTIONS). Незаписанное в журнал может потеряться при сжатии."}}'
