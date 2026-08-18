<!-- As duas bolhas de exemplo. Nao recebem mais `config`: a cor da marca chega
     pelas custom properties do wrapper (`--w-brand` / `--w-on-brand`), que sao
     as MESMAS que o servidor emite. Passar a cor por prop era o caminho pelo
     qual o preview conseguia mostrar uma cor que o widget nao usa. -->
<template>
  <div class="h-[calc(2rem*10)] px-4 overflow-y-auto">
    <div>
      <div>
        <div
          class="items-end flex justify-end ml-auto mb-1 mt-0 max-w-[85%] text-right"
        >
          <div
            class="rounded-[1.25rem] rounded-br-[0.25rem] bg-w-brand text-w-on-brand text-sm px-4 py-3"
          >
            <p class="m-0">
              {{ $t('INBOX_MGMT.WIDGET_BUILDER.BODY.USER_MESSAGE') }}
            </p>
          </div>
        </div>
      </div>

      <div
        class="shadow rounded-[1.25rem] rounded-bl-[0.25rem] px-4 py-3 inline-block text-sm text-n-slate-12 bg-n-solid-2"
      >
        <div>
          <p class="m-0">
            {{ $t('INBOX_MGMT.WIDGET_BUILDER.BODY.AGENT_MESSAGE') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
