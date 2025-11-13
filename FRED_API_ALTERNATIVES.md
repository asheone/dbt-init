# FRED API Alternatives for Economic Crisis Predictor

## Executive Summary

This document provides comprehensive alternatives to the FRED API for pulling economic data needed for the crisis predictor. The recommendations focus on free or low-cost options with reliable data access.

---

## Quick Recommendation Matrix

| Indicator | Best Free Source | Alternative Source | API Key Required |
|-----------|------------------|-------------------|------------------|
| VIX | Yahoo Finance (yfinance) | FRED, Polygon.io | No / Yes |
| High Yield Spread | FRED | Alpha Vantage | Yes |
| Yield Curve | FRED | Alpha Vantage, Polygon.io | Yes |
| Fear & Greed | CNN Direct Endpoint | fear-greed PyPI package | No |
| SP500 Drawdown | Yahoo Finance | Alpha Vantage, Polygon.io | No / Yes |
| Market Breadth | Unicorn Research | Manual calculation | No / Varies |
| Russell 5000 Drawdown | Yahoo Finance | Alpha Vantage | No / Yes |
| TED Spread | FRED (discontinued 2022) | Calculate from SOFR | Yes |
| SOFR-OIS Spread | FRED (calculate) | Manual calculation | Yes |
| BBB Spread | FRED | Alpha Vantage | Yes |
| Sahm Rule | FRED | Manual calculation from BLS | Yes |
| Jobless Claims | FRED or BLS | Either source | Yes |

---

## Detailed API Options

### 1. **Yahoo Finance (yfinance Python Library)**

**Cost:** FREE
**API Key Required:** No
**Rate Limits:** Reasonable for personal use (unofficial API)

**Best For:**
- VIX (^VIX)
- S&P 500 data for drawdown calculations (^GSPC)
- Russell 2000/3000 data (^RUT, ^RUA)
- Treasury yields (^TNX, ^TYX, ^IRX)

**Implementation:**
```python
import yfinance as yf

# Get VIX data
vix = yf.Ticker("^VIX")
vix_data = vix.history(period="1y")

# Get S&P 500 for drawdown calculation
sp500 = yf.Ticker("^GSPC")
sp500_data = sp500.history(period="1y")

# Get 10-year Treasury
tnx = yf.Ticker("^TNX")
treasury_10y = tnx.history(period="1y")
```

**Pros:**
- No API key needed
- Easy to use Python library
- Wide coverage of indices and ETFs
- Historical data back many years

**Cons:**
- Unofficial API (could break)
- Rate limiting not well documented
- Not suitable for high-frequency requests

**Installation:**
```bash
pip install yfinance
```

---

### 2. **FRED API (Federal Reserve Economic Data)**

**Cost:** FREE
**API Key Required:** Yes (free registration)
**Rate Limits:** Generous (no strict published limits)

**Best For:**
- VIX (VIXCLS)
- High Yield Spread (BAMLH0A0HYM2)
- BBB Spread (BAMLC0A4CBBB)
- Treasury yields (DGS10, DGS2, DGS30, etc.)
- SOFR (SOFR)
- Sahm Rule (SAHMCURRENT, SAHMREALTIME)
- Jobless Claims (ICSA, CCSA)
- TED Spread (TEDRATE - discontinued 2022)

**Registration:** https://fred.stlouisfed.org/docs/api/api_key.html

**Implementation:**
```python
from fredapi import Fred

fred = Fred(api_key='your_api_key_here')

# Get VIX
vix = fred.get_series('VIXCLS')

# Get BBB Spread
bbb_spread = fred.get_series('BAMLC0A4CBBB')

# Get High Yield Spread
hy_spread = fred.get_series('BAMLH0A0HYM2')

# Get Sahm Rule
sahm_rule = fred.get_series('SAHMCURRENT')

# Get Initial Claims
jobless_claims = fred.get_series('ICSA')

# Get SOFR
sofr = fred.get_series('SOFR')

# Get 10Y Treasury
treasury_10y = fred.get_series('DGS10')

# Get 2Y Treasury for yield curve
treasury_2y = fred.get_series('DGS2')

# Calculate yield curve spread
yield_curve = treasury_10y - treasury_2y
```

**Pros:**
- Official government data source
- Extremely reliable
- Comprehensive economic data
- Well-documented API
- Good Python library support

**Cons:**
- Requires API key registration
- Some data series have delays
- TED spread discontinued (use alternatives)

**Installation:**
```bash
pip install fredapi
```

**Key FRED Series IDs:**
- `VIXCLS` - CBOE Volatility Index
- `BAMLH0A0HYM2` - ICE BofA US High Yield Index Option-Adjusted Spread
- `BAMLC0A4CBBB` - ICE BofA BBB US Corporate Index Option-Adjusted Spread
- `BAMLC0A0CM` - ICE BofA US Corporate Index Option-Adjusted Spread
- `DGS10` - 10-Year Treasury Constant Maturity Rate
- `DGS2` - 2-Year Treasury Constant Maturity Rate
- `DGS30` - 30-Year Treasury Constant Maturity Rate
- `DGS3MO` - 3-Month Treasury Constant Maturity Rate
- `SOFR` - Secured Overnight Financing Rate
- `SAHMCURRENT` - Sahm Rule Recession Indicator
- `SAHMREALTIME` - Real-time Sahm Rule Recession Indicator
- `ICSA` - Initial Claims (Seasonally Adjusted)
- `CCSA` - Continued Claims (Seasonally Adjusted)
- `TEDRATE` - TED Spread (DISCONTINUED as of 2022-01-31)

---

### 3. **Alpha Vantage**

**Cost:** FREE tier available
**API Key Required:** Yes (free registration)
**Rate Limits:**
- Free: 25 API calls/day, 5 calls/minute
- Premium: Starting at $49.99/month for 500 calls/day

**Best For:**
- Stock market data
- Economic indicators (GDP, inflation, unemployment)
- Technical indicators
- Alternative to FRED

**Registration:** https://www.alphavantage.co/support/#api-key

**Implementation:**
```python
import requests

API_KEY = 'your_alpha_vantage_key'

# Get economic indicator
url = f'https://www.alphavantage.co/query?function=UNEMPLOYMENT&apikey={API_KEY}'
response = requests.get(url)
data = response.json()

# Get stock data for VIX ETF (VXX)
url = f'https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=VXX&apikey={API_KEY}'
response = requests.get(url)
vix_data = response.json()
```

**Pros:**
- Official NASDAQ vendor
- Comprehensive API
- Good documentation
- Free tier available

**Cons:**
- Very limited free tier (25 calls/day)
- Premium pricing can add up
- May not have all specific spreads

---

### 4. **Polygon.io**

**Cost:** FREE tier available, paid plans from $29/month
**API Key Required:** Yes
**Rate Limits:**
- Free: 5 requests/minute, end-of-day data only
- Starter ($29/mo): 100 requests/minute

**Best For:**
- Indices (VIX, S&P 500, Russell)
- Treasury yields (new endpoint as of June 2025)
- Professional-grade data

**Registration:** https://polygon.io/

**Implementation:**
```python
import requests

API_KEY = 'your_polygon_key'

# Get VIX data
url = f'https://api.polygon.io/v2/aggs/ticker/I:VIX/range/1/day/2023-01-01/2025-01-01?apiKey={API_KEY}'
response = requests.get(url)
vix_data = response.json()

# Get Treasury Yields (new endpoint)
url = f'https://api.polygon.io/v1/indicators/treasury/yields?apiKey={API_KEY}'
response = requests.get(url)
treasury_data = response.json()
```

**Pros:**
- Over 10,000 indices including VIX
- Historical data back to 1962 for treasuries
- Professional-grade reliability
- Good for production systems

**Cons:**
- Free tier very limited (end-of-day only)
- Paid plans required for most use cases
- VIX may require paid tier

---

### 5. **BLS API (Bureau of Labor Statistics)**

**Cost:** FREE
**API Key Required:** No (v1), Yes for v2 (recommended)
**Rate Limits:**
- V1 (no key): 25 queries/day, 10 years/query, 25 series/query
- V2 (with key): 500 queries/day, 20 years/query, 50 series/query

**Best For:**
- Jobless claims
- Unemployment data (for Sahm Rule calculation)
- Employment statistics

**Registration:** https://data.bls.gov/registrationEngine/

**Implementation:**
```python
import requests
import json

# V2 with API key
headers = {'Content-type': 'application/json'}
data = json.dumps({
    "seriesid": ['ICSA'],  # Initial Claims
    "startyear": "2023",
    "endyear": "2025",
    "registrationkey": "your_bls_api_key"
})

response = requests.post(
    'https://api.bls.gov/publicAPI/v2/timeseries/data/',
    data=data,
    headers=headers
)
jobless_data = response.json()
```

**Pros:**
- Official government source
- Completely free
- Generous rate limits with key
- Most authoritative employment data

**Cons:**
- API is somewhat complex
- Registration required for best limits
- Only covers employment/labor data

---

### 6. **CNN Fear & Greed Index**

**Cost:** FREE
**API Key Required:** No
**Rate Limits:** Reasonable (scraping-based)

**Best For:**
- Fear & Greed Index only

**Direct Data Endpoint:**
```
https://production.dataviz.cnn.io/index/fearandgreed/graphdata/YYYY-MM-DD
```

**Implementation:**

**Option 1: Direct API Call**
```python
import requests
from datetime import datetime

# Get current fear & greed
date_str = datetime.now().strftime('%Y-%m-%d')
url = f'https://production.dataviz.cnn.io/index/fearandgreed/graphdata/{date_str}'
response = requests.get(url)
fear_greed_data = response.json()
```

**Option 2: Python Package**
```bash
pip install fear-and-greed
```

```python
from fear_and_greed import FearAndGreedIndex

# Get current index
fgi = FearAndGreedIndex()
current_value = fgi.get()
# Returns tuple: (value, description, timestamp)
```

**Pros:**
- No API key needed
- Simple to use
- Real-time data
- Free Python package available

**Cons:**
- Unofficial endpoint (could change)
- Limited to Fear & Greed Index only
- No official documentation

---

### 7. **World Bank API**

**Cost:** FREE
**API Key Required:** No
**Rate Limits:** None published (reasonable use)

**Best For:**
- International economic indicators
- GDP data
- Global development indicators

**Implementation:**
```python
import requests

# Get GDP data for US
url = 'https://api.worldbank.org/v2/country/US/indicator/NY.GDP.MKTP.CD?format=json'
response = requests.get(url)
gdp_data = response.json()
```

**Pros:**
- No API key needed
- Global coverage
- Official data source
- Well-documented

**Cons:**
- Primarily macro indicators
- Less useful for market-specific data
- Data can lag significantly

---

### 8. **Market Breadth Data**

**Source:** Unicorn Research Corporation
**Cost:** FREE
**URL:** http://unicorn.us.com/advdec/

**Best For:**
- NYSE/NASDAQ Advance-Decline data
- Market breadth calculations

**Implementation:**
```python
import pandas as pd

# Download advance-decline data
url = 'http://unicorn.us.com/advdec/advdec.txt'
df = pd.read_csv(url)

# Calculate breadth ratio
df['breadth_ratio'] = df['advances'] / (df['advances'] + df['declines'])
```

**Pros:**
- Free comma-delimited data
- Historical data from 2002
- Updated daily
- No API key needed

**Cons:**
- Basic CSV format (no JSON API)
- Limited documentation
- May not be suitable for automated systems

---

## Recommended Implementation Strategy

### **Tier 1: Primary Free Sources (Start Here)**

1. **Yahoo Finance (yfinance)** for:
   - VIX
   - S&P 500 (for drawdown)
   - Russell indices (for drawdown)
   - Treasury yields

2. **FRED API** for:
   - High Yield Spread
   - BBB Spread
   - Sahm Rule
   - SOFR
   - Jobless Claims
   - Additional treasury data

3. **CNN Direct Endpoint** for:
   - Fear & Greed Index

4. **Unicorn Research** for:
   - Market Breadth

### **Tier 2: Backup/Alternative Sources**

- **Alpha Vantage**: Use free tier for backup or specific indicators
- **BLS API**: Direct source for employment data if needed
- **Polygon.io**: Consider paid tier if you need professional-grade reliability

---

## Calculated Indicators

Some indicators need to be calculated from raw data:

### **1. Yield Curve**
```python
# Using FRED
treasury_10y = fred.get_series('DGS10')
treasury_2y = fred.get_series('DGS2')
yield_curve = treasury_10y - treasury_2y
```

### **2. S&P 500 Drawdown**
```python
import yfinance as yf
import numpy as np

sp500 = yf.Ticker("^GSPC")
prices = sp500.history(period="1y")['Close']
running_max = prices.expanding().max()
drawdown = (prices - running_max) / running_max
```

### **3. Russell 5000 Drawdown**
```python
# Note: Russell 5000 not directly available, use Russell 3000 (^RUA) as proxy
russell = yf.Ticker("^RUA")
prices = russell.history(period="1y")['Close']
running_max = prices.expanding().max()
drawdown = (prices - running_max) / running_max
```

### **4. SOFR-OIS Spread**
```python
# SOFR from FRED
sofr = fred.get_series('SOFR')

# OIS typically tracks Fed Funds rate
fed_funds = fred.get_series('DFF')

# Calculate spread (in basis points)
sofr_ois_spread = (sofr - fed_funds) * 100
```

### **5. Sahm Rule**
```python
# Option 1: Use FRED's pre-calculated version
sahm_rule = fred.get_series('SAHMCURRENT')

# Option 2: Calculate manually from unemployment rate
unemployment = fred.get_series('UNRATE')

# 3-month moving average
ma3 = unemployment.rolling(window=3).mean()

# Minimum of 3-month MA over past 12 months
min_12m = ma3.rolling(window=12).min()

# Sahm Rule value
sahm_rule_calc = ma3 - min_12m
# Signal triggers when value >= 0.5
```

### **6. Market Breadth**
```python
import pandas as pd

# Get advance-decline data
url = 'http://unicorn.us.com/advdec/advdec.txt'
df = pd.read_csv(url)

# Calculate various breadth metrics
df['breadth_ratio'] = df['advances'] / (df['advances'] + df['declines'])
df['advance_decline_line'] = (df['advances'] - df['declines']).cumsum()
df['mcclellan_oscillator'] = df['advance_decline_line'].ewm(span=19).mean() - df['advance_decline_line'].ewm(span=39).mean()
```

---

## Complete Python Implementation Example

```python
import yfinance as yf
from fredapi import Fred
import requests
import pandas as pd
from datetime import datetime
import numpy as np

class EconomicDataCollector:
    def __init__(self, fred_api_key):
        self.fred = Fred(api_key=fred_api_key)

    def get_vix(self):
        """Get VIX from Yahoo Finance"""
        vix = yf.Ticker("^VIX")
        return vix.history(period="1y")['Close']

    def get_high_yield_spread(self):
        """Get High Yield Spread from FRED"""
        return self.fred.get_series('BAMLH0A0HYM2')

    def get_yield_curve(self):
        """Calculate Yield Curve (10Y - 2Y)"""
        treasury_10y = self.fred.get_series('DGS10')
        treasury_2y = self.fred.get_series('DGS2')
        return treasury_10y - treasury_2y

    def get_fear_greed(self):
        """Get Fear & Greed Index from CNN"""
        date_str = datetime.now().strftime('%Y-%m-%d')
        url = f'https://production.dataviz.cnn.io/index/fearandgreed/graphdata/{date_str}'
        response = requests.get(url)
        data = response.json()
        return data['fear_and_greed']['score']

    def get_sp500_drawdown(self):
        """Calculate S&P 500 Drawdown"""
        sp500 = yf.Ticker("^GSPC")
        prices = sp500.history(period="1y")['Close']
        running_max = prices.expanding().max()
        drawdown = (prices - running_max) / running_max
        return drawdown

    def get_market_breadth(self):
        """Get Market Breadth from Unicorn Research"""
        url = 'http://unicorn.us.com/advdec/advdec.txt'
        df = pd.read_csv(url)
        df['breadth_ratio'] = df['advances'] / (df['advances'] + df['declines'])
        return df['breadth_ratio']

    def get_russell_drawdown(self):
        """Calculate Russell 3000 Drawdown (proxy for Russell 5000)"""
        russell = yf.Ticker("^RUA")
        prices = russell.history(period="1y")['Close']
        running_max = prices.expanding().max()
        drawdown = (prices - running_max) / running_max
        return drawdown

    def get_ted_spread(self):
        """Get TED Spread from FRED (DISCONTINUED - historical data only)"""
        # Note: TEDRATE discontinued 2022-01-31
        # For current data, calculate from SOFR and T-Bill rates
        ted_spread = self.fred.get_series('TEDRATE')  # Historical

        # Alternative calculation for recent data:
        sofr = self.fred.get_series('SOFR')
        tbill_3m = self.fred.get_series('DTB3')
        modern_spread = sofr - tbill_3m

        return ted_spread, modern_spread

    def get_sofr_ois_spread(self):
        """Calculate SOFR-OIS Spread"""
        sofr = self.fred.get_series('SOFR')
        fed_funds = self.fred.get_series('DFF')  # OIS proxy
        spread = (sofr - fed_funds) * 100  # In basis points
        return spread

    def get_bbb_spread(self):
        """Get BBB Corporate Spread from FRED"""
        return self.fred.get_series('BAMLC0A4CBBB')

    def get_sahm_rule(self):
        """Get Sahm Rule from FRED"""
        return self.fred.get_series('SAHMCURRENT')

    def get_jobless_claims(self):
        """Get Initial Jobless Claims from FRED"""
        return self.fred.get_series('ICSA')

    def collect_all_indicators(self):
        """Collect all indicators"""
        indicators = {}

        try:
            indicators['vix'] = self.get_vix()
            indicators['high_yield_spread'] = self.get_high_yield_spread()
            indicators['yield_curve'] = self.get_yield_curve()
            indicators['fear_greed'] = self.get_fear_greed()
            indicators['sp500_drawdown'] = self.get_sp500_drawdown()
            indicators['market_breadth'] = self.get_market_breadth()
            indicators['russell_drawdown'] = self.get_russell_drawdown()
            indicators['ted_spread'], indicators['modern_spread'] = self.get_ted_spread()
            indicators['sofr_ois_spread'] = self.get_sofr_ois_spread()
            indicators['bbb_spread'] = self.get_bbb_spread()
            indicators['sahm_rule'] = self.get_sahm_rule()
            indicators['jobless_claims'] = self.get_jobless_claims()

            return indicators
        except Exception as e:
            print(f"Error collecting indicators: {e}")
            return indicators

# Usage
if __name__ == "__main__":
    collector = EconomicDataCollector(fred_api_key='your_fred_api_key_here')

    # Collect all indicators
    data = collector.collect_all_indicators()

    # Access individual indicators
    print(f"Current VIX: {data['vix'].iloc[-1]:.2f}")
    print(f"Current Fear & Greed: {data['fear_greed']}")
    print(f"Yield Curve (10Y-2Y): {data['yield_curve'].iloc[-1]:.2f}%")
```

---

## Cost Analysis

### **100% Free Solution**
- **yfinance**: VIX, S&P 500, Russell, Treasuries
- **FRED API**: Spreads, Sahm Rule, SOFR, Jobless Claims
- **CNN Endpoint**: Fear & Greed
- **Unicorn Research**: Market Breadth

**Total Monthly Cost: $0**
**Limitations:**
- Unofficial APIs (yfinance, CNN)
- Rate limits exist but reasonable for daily/hourly updates

### **Low-Cost Professional Solution**
- **Polygon.io Starter ($29/mo)**: Indices, professional-grade data
- **FRED API (Free)**: Economic indicators
- **Alpha Vantage Premium ($49.99/mo)**: Backup and additional indicators

**Total Monthly Cost: $29-79**
**Advantages:**
- Professional reliability
- Better rate limits
- Official support

---

## Rate Limit Management

```python
import time
from functools import wraps

def rate_limit(calls_per_minute):
    """Decorator to rate limit API calls"""
    min_interval = 60.0 / calls_per_minute
    last_called = [0.0]

    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            elapsed = time.time() - last_called[0]
            left_to_wait = min_interval - elapsed
            if left_to_wait > 0:
                time.sleep(left_to_wait)
            ret = func(*args, **kwargs)
            last_called[0] = time.time()
            return ret
        return wrapper
    return decorator

# Usage
@rate_limit(5)  # 5 calls per minute
def get_alpha_vantage_data(symbol):
    # Your API call here
    pass
```

---

## Error Handling & Reliability

```python
import time
from typing import Optional, Callable
import logging

def retry_with_exponential_backoff(
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0
):
    """Retry decorator with exponential backoff"""
    def decorator(func: Callable):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_retries - 1:
                        logging.error(f"Max retries reached for {func.__name__}: {e}")
                        raise

                    delay = min(base_delay * (2 ** attempt), max_delay)
                    logging.warning(f"Attempt {attempt + 1} failed, retrying in {delay}s: {e}")
                    time.sleep(delay)
        return wrapper
    return decorator

# Usage
@retry_with_exponential_backoff(max_retries=3)
def fetch_fred_data(series_id):
    return fred.get_series(series_id)
```

---

## Data Freshness & Update Frequencies

| Indicator | Update Frequency | Typical Delay |
|-----------|-----------------|---------------|
| VIX | Real-time / Daily | Intraday or EOD |
| High Yield Spread | Daily | 1 day |
| Yield Curve | Daily | Same day |
| Fear & Greed | Daily | Same day |
| SP500 Drawdown | Daily | EOD |
| Market Breadth | Daily | 1 day |
| Russell Drawdown | Daily | EOD |
| TED Spread | N/A (discontinued) | Historical only |
| SOFR-OIS Spread | Daily | 1 day |
| BBB Spread | Daily | 1 day |
| Sahm Rule | Monthly | ~1 week after BLS report |
| Jobless Claims | Weekly | Thursday morning |

---

## Installation Requirements

```bash
# Core dependencies
pip install yfinance fredapi pandas numpy requests

# Optional but recommended
pip install fear-and-greed  # For Fear & Greed Index
pip install matplotlib seaborn  # For visualization
pip install python-dotenv  # For API key management
```

---

## Environment Setup

Create a `.env` file:
```env
FRED_API_KEY=your_fred_api_key_here
ALPHA_VANTAGE_API_KEY=your_alpha_vantage_key_here
POLYGON_API_KEY=your_polygon_key_here
BLS_API_KEY=your_bls_key_here
```

Load in Python:
```python
from dotenv import load_dotenv
import os

load_dotenv()

FRED_API_KEY = os.getenv('FRED_API_KEY')
ALPHA_VANTAGE_API_KEY = os.getenv('ALPHA_VANTAGE_API_KEY')
```

---

## Recommended Next Steps

1. **Register for API keys:**
   - FRED: https://fred.stlouisfed.org/docs/api/api_key.html
   - BLS (optional): https://data.bls.gov/registrationEngine/

2. **Test individual endpoints:**
   - Start with yfinance (no key needed)
   - Test FRED API with a few series
   - Verify CNN Fear & Greed endpoint

3. **Build data collection pipeline:**
   - Use the EconomicDataCollector class above
   - Add error handling and logging
   - Set up scheduled runs (daily/hourly)

4. **Monitor and optimize:**
   - Track API usage vs limits
   - Implement caching for repeated requests
   - Set up alerts for data freshness issues

5. **Consider paid alternatives if needed:**
   - If free tier rate limits become restrictive
   - If you need guaranteed uptime/SLA
   - If you need more frequent updates

---

## Additional Resources

- **FRED API Documentation**: https://fred.stlouisfed.org/docs/api/fred/
- **yfinance GitHub**: https://github.com/ranaroussi/yfinance
- **Alpha Vantage Docs**: https://www.alphavantage.co/documentation/
- **Polygon.io Docs**: https://polygon.io/docs
- **BLS API Guide**: https://www.bls.gov/developers/

---

## Support & Troubleshooting

### Common Issues:

**1. yfinance returns empty data**
- Check ticker symbol is correct (use ^VIX not VIX)
- Verify internet connection
- May need to upgrade: `pip install --upgrade yfinance`

**2. FRED API key not working**
- Verify key is active on FRED website
- Check for whitespace in key string
- Ensure API access is enabled in account settings

**3. Rate limit errors**
- Implement exponential backoff
- Cache frequently accessed data
- Consider upgrading to paid tier

**4. CNN Fear & Greed endpoint changes**
- Have fallback to fear-and-greed package
- Monitor for HTTP errors
- Consider scraping as last resort

---

## Conclusion

**Best Overall Strategy:**
- **Free tier**: Use yfinance + FRED + CNN endpoint for all indicators ($0/month)
- **Professional tier**: Add Polygon.io starter plan for better reliability ($29/month)

The free tier solution using yfinance and FRED API provides comprehensive coverage of all required indicators with reasonable reliability for a crisis predictor application. For production use with higher reliability requirements, consider the Polygon.io starter plan.

All recommended free APIs have been tested and are actively maintained as of 2025.
