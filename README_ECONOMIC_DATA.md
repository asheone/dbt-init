# Economic Data Collection - Quick Start Guide

This guide helps you get started with collecting economic data using free APIs as alternatives to FRED.

## Quick Setup (5 minutes)

### 1. Install Dependencies

```bash
pip install -r requirements_economic_data.txt
```

### 2. Get Your Free FRED API Key

1. Go to https://fred.stlouisfed.org/
2. Click "My Account" → "API Keys"
3. Request a new API key (instant approval)
4. Copy your API key

### 3. Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and add your FRED API key
nano .env  # or use your preferred editor
```

Replace `your_fred_api_key_here` with your actual FRED API key.

### 4. Test the Setup

```bash
python economic_data_collector.py
```

You should see output showing the latest economic indicators!

## Basic Usage

### Get Latest Values

```python
from economic_data_collector import EconomicDataCollector
import os
from dotenv import load_dotenv

load_dotenv()

collector = EconomicDataCollector(fred_api_key=os.getenv('FRED_API_KEY'))
latest = collector.get_latest_values()

print(f"VIX: {latest['vix']:.2f}")
print(f"Yield Curve: {latest['yield_curve']:.3f}%")
print(f"Sahm Rule: {latest['sahm_rule']:.3f}")
```

### Get Historical Data

```python
# Get VIX for the past year
vix_data = collector.get_vix(period="1y")
print(vix_data.tail())

# Get yield curve since 2020
yield_curve = collector.get_yield_curve(start_date="2020-01-01")
print(yield_curve.tail())
```

### Collect All Indicators

```python
# Get all indicators at once
all_data = collector.collect_all_indicators(start_date="2024-01-01")

# Access individual indicators
vix = all_data['vix']
sahm_rule = all_data['sahm_rule']
fear_greed = all_data['fear_greed']
```

## Available Indicators

| Indicator | Method | Data Source | API Key Required |
|-----------|--------|-------------|------------------|
| VIX | `get_vix()` | Yahoo Finance | No |
| High Yield Spread | `get_high_yield_spread()` | FRED | Yes |
| Yield Curve | `get_yield_curve()` | FRED | Yes |
| Fear & Greed | `get_fear_greed()` | CNN | No |
| S&P 500 Drawdown | `get_sp500_drawdown()` | Yahoo Finance | No |
| Market Breadth | `get_market_breadth()` | Unicorn Research | No |
| Russell Drawdown | `get_russell_drawdown()` | Yahoo Finance | No |
| TED Spread | `get_ted_spread()` | FRED | Yes |
| SOFR-OIS Spread | `get_sofr_ois_spread()` | FRED | Yes |
| BBB Spread | `get_bbb_spread()` | FRED | Yes |
| Sahm Rule | `get_sahm_rule()` | FRED | Yes |
| Jobless Claims | `get_jobless_claims()` | FRED | Yes |

## Recession Signal Detection

The code includes built-in recession signal detection:

```python
latest = collector.get_latest_values()

# Check for inverted yield curve
if latest['yield_curve'] < 0:
    print("WARNING: Yield curve is inverted!")

# Check Sahm Rule
if latest['sahm_rule'] >= 0.5:
    print("WARNING: Sahm Rule recession indicator triggered!")

# Check elevated VIX
if latest['vix'] > 30:
    print("WARNING: VIX shows high market volatility!")
```

## Error Handling

The collector includes automatic retry logic with exponential backoff:

```python
# Automatically retries up to 3 times on failure
try:
    vix = collector.get_vix()
except Exception as e:
    print(f"Failed after retries: {e}")
```

## Rate Limiting

Rate limiting is built-in to respect API limits:

```python
# Automatically limits to 10 calls per minute for Yahoo Finance
vix = collector.get_vix()  # Rate limited automatically
```

## Troubleshooting

### "FRED API key required"
- Make sure you've set `FRED_API_KEY` in your `.env` file
- Verify the key is valid by logging into fred.stlouisfed.org

### "No data returned"
- Check your internet connection
- Verify the date range (some series don't have recent data)
- Check FRED website to confirm the series is still active

### Import errors
- Run `pip install -r requirements_economic_data.txt`
- Make sure you're using Python 3.8 or later

### Rate limit errors
- The code includes automatic rate limiting
- If you still hit limits, increase the delay between calls
- Consider caching data for repeated access

## Cost

**FREE Option (Recommended):**
- FRED API: Free (generous limits)
- Yahoo Finance: Free (unofficial but reliable)
- CNN Fear & Greed: Free (no key needed)
- Unicorn Research: Free (CSV download)

**Total Monthly Cost: $0**

## Next Steps

1. Read the full documentation in `FRED_API_ALTERNATIVES.md`
2. Customize the collector for your specific needs
3. Set up scheduled data collection (cron job or Task Scheduler)
4. Integrate with your crisis predictor model

## Resources

- [FRED API Documentation](https://fred.stlouisfed.org/docs/api/fred/)
- [yfinance GitHub](https://github.com/ranaroussi/yfinance)
- [Full API Alternatives Guide](FRED_API_ALTERNATIVES.md)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the detailed documentation in `FRED_API_ALTERNATIVES.md`
3. Check FRED API status at https://fred.stlouisfed.org/

## License

This code is provided as-is for educational and research purposes.
