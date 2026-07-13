# frozen_string_literal: true

require 'rails_helper'

# Builder de payload interativo compartilhado por WhatsApp Cloud e 360dialog. Cobre a decisão
# botão(≤3)/lista(>3), a descrição nas linhas de lista (F1 send_interactive) e o cap defensivo de 10.
# Sem HTTP — testamos apenas os helpers de montagem de payload com um Message double.
RSpec.describe Whatsapp::Providers::BaseService do
  subject(:service) { described_class.new(whatsapp_channel: instance_double(Channel::Whatsapp)) }

  def message_double(items, body: 'Escolha uma opção:')
    instance_double(Message, content_attributes: { 'items' => items }, outgoing_content: body)
  end

  describe '#create_payload_based_on_items' do
    context 'with <= 3 items' do
      it 'builds a button payload mapping value->id and title' do
        items = [{ 'title' => 'Sim', 'value' => 'sim' }, { 'title' => 'Não', 'value' => 'nao' }]
        payload = service.create_payload_based_on_items(message_double(items))

        expect(payload[:type]).to eq('button')
        expect(payload[:body][:text]).to eq('Escolha uma opção:')
        buttons = JSON.parse(payload[:action])['buttons']
        expect(buttons.map { |b| b['reply']['id'] }).to eq(%w[sim nao])
        expect(buttons.map { |b| b['reply']['title'] }).to eq(%w[Sim Não])
      end
    end

    context 'with > 3 items' do
      it 'builds a list payload whose rows carry description only when present' do
        items = [
          { 'title' => 'A', 'value' => 'a', 'description' => 'desc A' },
          { 'title' => 'B', 'value' => 'b' },
          { 'title' => 'C', 'value' => 'c' },
          { 'title' => 'D', 'value' => 'd' }
        ]
        payload = service.create_payload_based_on_items(message_double(items))

        expect(payload[:type]).to eq('list')
        rows = JSON.parse(payload[:action])['sections'].first['rows']
        expect(rows.length).to eq(4)
        expect(rows.first).to eq({ 'id' => 'a', 'title' => 'A', 'description' => 'desc A' })
        expect(rows[1]).to eq({ 'id' => 'b', 'title' => 'B' })
        expect(rows[1]).not_to have_key('description')
      end

      it 'caps rows at 10 (defensive last line vs Meta)' do
        items = Array.new(15) { |i| { 'title' => "T#{i}", 'value' => "v#{i}" } }
        payload = service.create_payload_based_on_items(message_double(items))

        rows = JSON.parse(payload[:action])['sections'].first['rows']
        expect(rows.length).to eq(10)
      end
    end
  end

  describe '#create_rows' do
    it 'includes description only when present' do
      rows = service.create_rows(
        [{ 'title' => 'A', 'value' => 'a', 'description' => 'd' }, { 'title' => 'B', 'value' => 'b' }]
      )
      expect(rows[0]).to eq({ 'id' => 'a', 'title' => 'A', 'description' => 'd' })
      expect(rows[1]).to eq({ 'id' => 'b', 'title' => 'B' })
    end

    it 'caps at 10 rows' do
      items = Array.new(12) { |i| { 'title' => "T#{i}", 'value' => "v#{i}" } }
      expect(service.create_rows(items).length).to eq(10)
    end
  end

  describe '#create_buttons (unchanged — WhatsApp buttons have no description)' do
    it 'maps value->id and title and ignores any description' do
      buttons = service.create_buttons([{ 'title' => 'Sim', 'value' => 'sim', 'description' => 'ignored' }])
      expect(buttons.first).to eq({ :type => 'reply', 'reply' => { 'id' => 'sim', 'title' => 'Sim' } })
    end
  end
end
