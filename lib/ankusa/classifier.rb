module Ankusa

  class Classifier
    attr_reader :classnames

    def initialize(storage)
      @storage = storage
      @storage.init_tables
      @classnames = @storage.classnames
    end

    # text can be either an array of strings or a string
    # klass is a symbol
    def train(klass, text)
      th = TextHash.new(text)
      th.each { |word, count|
        @storage.incr_word_count klass, word, count
        yield word, count if block_given?
      }
      @storage.incr_total_word_count klass, th.word_count
      doccount = (text.kind_of? Array) ? text.length : 1
      @storage.incr_doc_count klass, doccount
      @classnames << klass if not @classnames.include? klass
      th
    end

    # text can be either an array of strings or a string
    # klass is a symbol
    def untrain(klass, text)
      th = TextHash.new(text)
      th.each { |word, count|
        @storage.incr_word_count klass, word, -count
        yield word, count if block_given?
      }
      @storage.incr_total_word_count klass, -th.word_count
      doccount = (text.kind_of? Array) ? text.length : 1
      @storage.incr_doc_count klass, -doccount
      th
    end

    def classify(text, classes=nil)
      # return the most probable class
      classifications(text, classes).sort_by { |c| -c[1] }.first.first
    end
    
    # Classes is an array of classes to look at
    def classifications(text, classnames=nil)
      classnames ||= @classnames
      result = Hash.new 0

      TextHash.new(text).each { |word, count|
        probs = get_word_probs(word, classnames)
        classnames.each { |k| result[k] += (Math.log(probs[k]) * count) }
      }

      # add the prior and exponentiate
      doc_count_total = (@storage.doc_count_total(classnames) + classnames.length).to_f
      classnames.each { |k| 
        result[k] += Math.log((@storage.get_doc_count(k) + 1).to_f / doc_count_total) 
        result[k] = Math.exp(result[k])
      }
      
      # normalize to get probs
      sum = result.values.inject { |x,y| x+y }
      classnames.each { |k| result[k] = result[k] / sum }
      result
    end

    protected
    def get_word_probs(word, classnames)
      probs = Hash.new 0
      @storage.get_word_counts(word).each { |k,v| probs[k] = v if classnames.include? k }
      classnames.each { |cn| 
        # use a laplacian smoother
        probs[cn] = (probs[cn] + 1).to_f / (@storage.get_total_word_count(cn) + 1).to_f
      }
      probs
    end

  end

end
