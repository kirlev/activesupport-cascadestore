require 'rspec'
require 'activesupport-cascadestore'

describe ActiveSupport::Cache::CascadeStore do
  let(:cache) {
    ActiveSupport::Cache.lookup_store(:cascade_store, {
      :expires_in => 60.seconds,
      :stores => [
        :memory_store,
        [:memory_store, :expires_in => 30.seconds]
      ]
    })
  }

  let(:store1) { cache.stores.first }
  let(:store2) { cache.stores.last }

  describe "initialization" do
    it "sets expiration" do
      expect(store1.options[:expires_in]).to eq 60
      expect(store2.options[:expires_in]).to eq 30
    end
  end

  it "returns nil on a miss" do
    expect(cache.read('duduzar')).to be_nil
    expect(cache.fetch('duduzar')).to be_nil
  end

  it "supports a weird key" do
    crazy_key = "#/:*(<+=> )&$%@?;'\"\'`~-"

    cache.write(crazy_key, "1", :raw => true)
    expect(cache.read(crazy_key)).to eq '1'
  end

  it "supports a long key" do
    long_key = "x" * 1000

    cache.write(long_key, "1", :raw => true)
    expect(cache.read(long_key)).to eq '1'
  end

  describe ".write" do
    it "writes to all stores" do
      expect(cache.read('duduzar')).to be_nil

      cache.write('konohamaru', 'hokage')
      expect(store1.read('konohamaru')).to eq 'hokage'
      expect(store2.read('konohamaru')).to eq 'hokage'
    end
  end

  describe ".read" do
    context "when hit in first store" do
      it "returns the result without cascading" do
        cache.write('foo', 'bar')
        expect(store1).to receive(:read_entry).and_call_original
        expect(store2).to_not receive(:read_entry)

        expect(cache.read('foo')).to eq 'bar'
      end
    end
    context "when hit in second store" do
      it "returns the result" do
        store2.write('foo', 'bar')
        expect(store1).to receive(:read_entry).and_call_original
        expect(store2).to receive(:read_entry).and_call_original

        expect(cache.read('foo')).to eq 'bar'
      end
    end
    context "when miss in all stores" do
      it "returns nil" do
        expect(store1).to receive(:read_entry).and_call_original
        expect(store2).to receive(:read_entry).and_call_original

        expect(cache.read('foo')).to be_nil
      end
    end
  end

  describe ".delete" do
    it "deletes from all stores" do
      store1.write('foo', 'bar')
      store2.write('foo', 'bar')

      cache.delete('foo')

      expect(store1.read('foo')).to be_nil
      expect(store2.read('foo')).to be_nil
    end
  end

  describe ".increment" do
    it "returms num when only one cache is hit" do
      store1.write('foo', 2)
      expect(cache.increment('foo')).to eq 3
    end

    it "increments correctly" do
      cache.write('foo', 1, :raw => true)

      expect(cache.read('foo').to_i).to eq 1
      expect(cache.increment('foo')).to eq 2
      expect(cache.read('foo').to_i).to eq 2
    end
  end

  describe ".decrement" do
    it "returms num when only one cache is hit" do
      store1.write('foo', 2)
      expect(cache.decrement('foo')).to eq 1
    end

    it "decrements correctly" do
      cache.write('foo', 3, :raw => true)

      expect(cache.read('foo').to_i).to eq 3
      expect(cache.decrement('foo')).to eq 2
      expect(cache.read('foo').to_i).to eq 2
    end
  end

  describe ".delete_matched" do
    it "deletes the matched keys" do
      cache.write("foo", "bar")
      cache.write("fu", "baz")
      cache.write("foo/bar", "baz")
      cache.write("fu/baz", "bar")
      cache.delete_matched(/oo/)

      expect(cache.exist?("foo")).to be_falsy
      expect(cache.exist?("fu")).to be_truthy
      expect(cache.exist?("foo/bar")).to be_falsy
      expect(cache.exist?("fu/baz")).to be_truthy
    end
  end

  describe ".clear" do
    it "clears all the cache stores" do
      cache.write('foo', 'bar')
      cache.clear

      expect(cache.read('foo')).to be_nil
    end
  end

  describe "race condition protection" do
    let(:time) { Time.local(1984, 3, 18) }

    it "expire the cache" do
      allow(Time).to receive(:now).and_return(time)

      cache.write('foo', 'bar')
      expect(cache.read('foo')).to eq 'bar'

      allow(Time).to receive(:now).and_return(time + 61.seconds)
      expect(cache.read('foo')).to be_nil
    end

    it "protects from race condition" do
      allow(Time).to receive(:now).and_return(time)
      cache.write('foo', 'bar')
      expect(cache.read('foo')).to eq 'bar'

      allow(Time).to receive(:now).and_return(time + 61.seconds)

      result = cache.fetch('foo', race_condition_ttl: 10.seconds) do
        cache.read('foo')
        cache.fetch('foo', race_condition_ttl: 10.seconds) do
          #this block will not be called
          'kacha'
        end
      end

      expect(result).to eq 'bar'
    end
  end
end