require 'rails_helper'

RSpec.describe NpsSurveys::ScoreValidator do
  def extract(input)
    described_class.validate_and_extract(input)
  end

  describe 'bare numbers' do
    it 'extracts single digits and 10' do
      expect(extract('8')).to eq(8)
      expect(extract('0')).to eq(0)
      expect(extract('10')).to eq(10)
    end

    it 'tolerates trailing punctuation and whitespace' do
      expect(extract('  9! ')).to eq(9)
      expect(extract("10\n")).to eq(10)
    end
  end

  describe '"nota" patterns' do
    it 'extracts from "nota N"' do
      expect(extract('nota 9')).to eq(9)
      expect(extract('Minha NOTA: 7')).to eq(7)
    end

    it 'extracts from "minha nota é N"' do
      expect(extract('minha nota é 10')).to eq(10)
    end
  end

  describe 'score followed by a comment' do
    it 'reads the leading score before free text' do
      expect(extract('8, ótimo atendimento')).to eq(8)
      expect(extract('10 recomendo demais')).to eq(10)
    end

    it 'reads "nota N" embedded in a longer sentence' do
      expect(extract('Adorei tudo, nota 10 com certeza')).to eq(10)
    end
  end

  describe 'short survey-style patterns' do
    it 'reads X/10 and "X de 10"' do
      expect(extract('8/10')).to eq(8)
      expect(extract('9 de 10')).to eq(9)
    end

    it 'reads "score: N", "rating: N" and star phrasing' do
      expect(extract('score: 7')).to eq(7)
      expect(extract('rating: 6')).to eq(6)
      expect(extract('9 estrelas')).to eq(9)
      expect(extract('9 stars')).to eq(9)
    end
  end

  describe 'quoted name + score on the next line (WhatsApp)' do
    it 'reads the score after a colon and newline' do
      expect(extract("**Maria**:\n10")).to eq(10)
    end
  end

  describe 'invalid or empty input' do
    it 'returns nil for blank input' do
      expect(extract('')).to be_nil
      expect(extract(nil)).to be_nil
      expect(extract('   ')).to be_nil
    end

    it 'returns nil for non-numeric words' do
      expect(extract('onze')).to be_nil
      expect(extract('?')).to be_nil
      expect(extract('obrigado')).to be_nil
    end
  end

  describe 'unicode / invisible-character noise' do
    it 'still recognizes the score after normalization' do
      expect(extract('​10﻿')).to eq(10)
    end
  end
end
